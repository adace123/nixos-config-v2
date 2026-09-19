/**
 * OpenCode session headers for Pi's extension-initiated model calls.
 *
 * OpenCode Go/Zen reject a request that carries no `x-opencode-session` with
 * `400 MissingSessionID`: the id is how they route a conversation to a backend
 * and keep its prompt cache warm (https://opencode.ai/docs/go/#where-can-i-use-it).
 * Pi sends it on its own traffic — the agent loop hands its session id to the
 * model runtime, whose `transformHeaders` merges `x-opencode-session` /
 * `x-opencode-client` before the request leaves.
 *
 * That merge lives in the coding agent's stream wrapper, so it covers only Pi's
 * main request path. An extension that runs a model itself — what any
 * extension must do to call a model *inside* a tool call, and what
 * `@juicesharp/rpiv-advisor` does for its reviewer side-call — goes through
 * `ModelRuntime.completeSimple` / `prepareRequest`, which apply the provider's
 * configured headers but never Pi's per-session ones. With an `opencode-go`
 * reviewer the advisor therefore returns `400 MissingSessionID` instead of an
 * answer, and the tool is unusable while the executor model works fine.
 *
 * The missing header can be supplied declaratively: `pi.registerProvider()`
 * with headers and no `models` preserves the provider's models and auth, and
 * those headers are resolved into every request's auth headers on *both* paths
 * (`resolveProviderAuth` -> `withConfiguredAuth`). Registering the session's own
 * id — the same `sessionManager.getSessionId()` that Pi passes to its wrapper as
 * `options.sessionId` — makes the two paths agree, so Pi's own traffic is
 * unchanged and extension side-calls start working.
 *
 * `session_start` fires once per session (startup, new, resume, fork, reload)
 * and extensions are re-bound there by design, so the header always tracks the
 * current session instead of the one the process started with. Registration is
 * skipped when `getProvider()` has nothing, so an unconfigured provider is never
 * introduced. Nothing else is sent: a provider outside OpenCode is left alone.
 *
 * Upstream: rpiv-advisor 2.10.1 (latest) still omits the header on this path, so
 * this stays until it does not.
 */

const OPENCODE_HOST = "opencode.ai";
const SESSION_HEADER = "x-opencode-session";
const CLIENT_HEADER = "x-opencode-client";

/** Providers whose requests must carry a session id, by id or by endpoint host. */
const OPENCODE_PROVIDER_IDS = ["opencode", "opencode-go"];

interface ProviderLike {
  id: string;
  baseUrl?: string;
}

/** Mirrors the host check Pi itself uses to decide who needs the header. */
function needsSessionHeader(provider: ProviderLike): boolean {
  if (OPENCODE_PROVIDER_IDS.includes(provider.id)) {
    return true;
  }
  try {
    return new URL(provider.baseUrl ?? "").hostname === OPENCODE_HOST;
  } catch {
    return false;
  }
}

/** The slice of Pi's extension API this file depends on. */
interface PiApi {
  on(
    event: "session_start",
    handler: (event: unknown, ctx: PiContext) => unknown
  ): unknown;
  registerProvider(
    providerId: string,
    config: { headers?: Record<string, string> }
  ): unknown;
}

interface PiContext {
  sessionManager: { getSessionId(): string | undefined };
  modelRegistry: { getProvider(providerId: string): ProviderLike | undefined };
}

export default function (pi: PiApi): void {
  const apply = (ctx: PiContext): void => {
    const sessionId = ctx.sessionManager.getSessionId();
    if (!sessionId) {
      return;
    }
    for (const providerId of OPENCODE_PROVIDER_IDS) {
      const provider = ctx.modelRegistry.getProvider(providerId);
      if (!provider || !needsSessionHeader(provider)) {
        continue;
      }
      pi.registerProvider(providerId, {
        headers: {
          [SESSION_HEADER]: sessionId,
          [CLIENT_HEADER]: "pi",
        },
      });
    }
  };

  pi.on("session_start", (_event, ctx) => apply(ctx));
}
