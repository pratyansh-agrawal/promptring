# Contributing to promptring

Thanks for your interest! 🎺

## Ground rules

- **All changes go through a pull request.** Direct pushes to `main` are not
  accepted — the branch is protected.
- External contributors: **fork** the repo, push to a branch on your fork, and
  open a PR against `main`.
- Every PR requires review and approval from a [code owner](.github/CODEOWNERS)
  before it can be merged.
- Keep PRs focused and describe what changed and why.

## Local setup

```sh
git clone https://github.com/pratyansh-agrawal/promptring.git
cd promptring
./install.sh        # macOS / Linux / WSL  (Windows: powershell -File install.ps1)
```

See the [README](README.md) for how everything fits together, and
[`tests/README.md`](tests/README.md) for the test layout.

## Testing your change

```sh
# 1. cross-platform unit tests (run anywhere with python3)
python3 tests/test_core.py

# 2. per-OS smoke test (dry run asserts dispatch; --live shows banners)
tests/smoke.sh                       # macOS / Linux / WSL
#  powershell -File tests\smoke.ps1  # Windows

# 3. fire a banner through the orchestrator exactly as the hook would
~/.copilot/promptring/bin/promptring.py done "testing my change"
```

Please run the unit tests and confirm a banner appears with the bundled sound
before opening a PR. If you touched a native delivery backend, validate it on
that OS using the manual checklist in `tests/README.md`.
