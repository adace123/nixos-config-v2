---
name: browser-routing
description: Read before any web or browser task. Routes to ego lite (headed, the user's real profile) when a UI, login, or visual check is needed, and agent-browser (headless CLI) when it is not. OMP's built-in browser prelude is disabled; never re-enable it.
---

# Browser routing

OMP's built-in browser prelude is disabled in `~/.omp/agent/config.yml`
(`browser.enabled: false`). Do not re-enable it, and do not drive Chromium
yourself through `eval`, bash, Puppeteer, or a CDP URL instead.

Pick one of two tools before opening a page.

## ego lite — headed, real profile

Use when the task needs a rendered UI or the user's browser state:

| Signal | Why |
| --- | --- |
| UI work | layout, rendering, visual verification, screenshots a human reviews |
| Logins and sessions | the real profile's cookies and signed-in tabs come along |
| Hardened targets | real fingerprint and display environment, lowest detection baseline |
| Collaboration | the user can watch, point, or take over mid-task |

```sh
ego-browser skill    # usage guide for the installed ego lite; follow it
```

Read the `ego-browser` skill first. Iterating on a web UI without looking at it
is not verification.

## agent-browser — headless CLI

Use when no UI is needed — public pages, bulk work, servers, pipelines:

| Signal | Why |
| --- | --- |
| Content | docs, search results, one-off page reads |
| Bulk | crawls over many pages; small, dense, parallel instances |
| Output | PDF generation, extraction to files |
| Environment | CI, servers, no display; cheap per instance |

```sh
agent-browser read <url>              # quick page-to-text
agent-browser skills get core --full  # full command set, once per session
```

## Decision order

1. Needs a UI, a logged-in profile, or a human watching? → ego lite.
2. Otherwise → agent-browser.
3. Neither available? Report the blocker. Do not fall back to the built-in
   browser or hand-rolled CDP.
