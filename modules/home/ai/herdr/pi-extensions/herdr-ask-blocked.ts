/**
 * A pane that is waiting on a question is not a pane that is working.
 *
 * Pi's `ask_user_question` tool (from `@juicesharp/rpiv-ask-user-question`) runs
 * inside a tool call, so the turn is still active while the questionnaire sits
 * on screen. herdr's pi integration beside this file only knows whether a turn
 * is running, so it keeps reporting `working`, and everything that reads herdr
 * believes it: the sidebar spinner never stops, and the kanban board leaves the
 * card in **In Progress** instead of moving it to **Blocked** until you answer.
 *
 * rpiv-ask-user-question already publishes exactly the missing fact on Pi's
 * event bus — `rpiv:ask-user:blocked` with `active: true` while the
 * questionnaire waits and `active: false` in its `finally`. herdr's integration
 * consumes the sibling `herdr:blocked` channel for the same purpose (that is how
 * pi-subagents reports a run that needs attention). So the fix is a translation
 * between the two, here, rather than teaching every consumer of herdr's state to
 * guess from a pane's screen — which herdr deliberately does not do for
 * integrations that report their own lifecycle.
 *
 * The pair is counted by the integration (`blockedCount`), so this emits at most
 * one `active: true` per `active: false`, guarded rather than trusting the
 * source to be balanced. A turn that ends with the questionnaire still open —
 * session switch, an extension replaced mid-wait — is closed off by
 * `agent_settled`, so a stuck count cannot leave the pane blocked forever.
 *
 * It lives beside `herdr-agent-state.ts` on purpose: that file is herdr-managed
 * and is replaced by `herdr integration install pi`, and its own header says to
 * add custom hooks beside it instead of editing it.
 */

const ASK_PROMPT_EVENT = "rpiv:ask-user:prompt";
const ASK_BLOCKED_EVENT = "rpiv:ask-user:blocked";
const HERDR_BLOCKED_EVENT = "herdr:blocked";

const FALLBACK_LABEL = "waiting for user input";
const MAX_LABEL_CHARS = 100;

/** Same gate the integration uses: outside a herdr pane there is nobody to tell. */
function enabled(): boolean {
  return process.env.HERDR_ENV === "1" && !!process.env.HERDR_PANE_ID;
}

/** The question text as one short line — herdr shows it as the pane's message. */
function labelFromPrompt(data: unknown, fallback: string): string {
  const questions = (data as { questions?: unknown })?.questions;
  if (!Array.isArray(questions)) return fallback;
  const first = questions.find((question) => {
    const text = (question as { question?: unknown })?.question;
    return typeof text === "string" && text.trim().length > 0;
  }) as { question?: string; header?: string } | undefined;
  if (!first) return fallback;
  const text = first.question ?? first.header ?? fallback;
  const collapsed = text
    .replace(/[\u0000-\u001f\u007f]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!collapsed) return fallback;
  return collapsed.length > MAX_LABEL_CHARS
    ? `${collapsed.slice(0, MAX_LABEL_CHARS - 1).trimEnd()}…`
    : collapsed;
}

export default function (pi: {
  events: {
    on(event: string, handler: (data: unknown) => void): unknown;
    emit(event: string, data: unknown): unknown;
  };
  on(event: string, handler: (event: unknown, ctx: unknown) => unknown): unknown;
}): void {
  if (!enabled() || !pi?.events) {
    return;
  }

  let blocked = false;
  let label = FALLBACK_LABEL;

  const raise = (): void => {
    if (blocked) {
      return;
    }
    blocked = true;
    pi.events.emit(HERDR_BLOCKED_EVENT, { active: true, label });
  };

  const lower = (): void => {
    if (!blocked) {
      return;
    }
    blocked = false;
    pi.events.emit(HERDR_BLOCKED_EVENT, { active: false });
  };

  // The prompt event fires before the blocked one, so the label is the question
  // the pane is actually waiting on rather than a generic phrase.
  pi.events.on(ASK_PROMPT_EVENT, (data) => {
    label = labelFromPrompt(data, FALLBACK_LABEL);
  });

  pi.events.on(ASK_BLOCKED_EVENT, (data) => {
    if ((data as { active?: boolean })?.active) {
      raise();
    } else {
      lower();
    }
  });

  // Safety net only: the questionnaire's `finally` is what normally clears this.
  pi.on("agent_settled", () => lower());
  pi.on("session_switch", () => lower());
}
