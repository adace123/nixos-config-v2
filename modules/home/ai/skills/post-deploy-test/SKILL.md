---
name: post-deploy-test
description: Run deterministic post-deployment tests on NixOS hosts. Use after deploying changes to verify the system works correctly. Also use when asked to add, update, or create post-deploy tests.
---

# Post-Deploy Testing

After deploying changes to a NixOS host, run the test suite to verify
the system is healthy. Tests are deterministic shell scripts under
`tests/` — each exits 0 on pass or non-zero with diagnostic output on
failure.

## Running Tests

```bash
~/.pi/agent/skills/post-deploy-test/tests/run-all.sh
```

Or run a single test:

```bash
~/.pi/agent/skills/post-deploy-test/tests/01-check-hass-logs.sh
```

Tests are idempotent and safe to run multiple times. Every script resolves its
own directory, so the suite also runs from a checkout
(`modules/home/ai/skills/post-deploy-test/tests/run-all.sh`) and can be invoked
from any working directory.

## Adding New Tests

Each test is a standalone shell script in `tests/` named
`NN-description.sh`. Conventions:

- Exit 0 on pass, non-zero on failure
- Print diagnostic output to stdout on failure
- Source `tests/test-lib.sh` for shared helpers
- Keep tests focused on one thing

The suite is deployed to `~/.pi/agent/skills/post-deploy-test` by
`modules/home/ai/pi.nix`; that `home.file` link is read-only, so make edits in
the repo and re-run `just switch`.
