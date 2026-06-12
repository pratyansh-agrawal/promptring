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
./install.sh        # builds Promptring.app + installs the hook (macOS)
```

See the [README](README.md) for how everything fits together.

## Testing your change

```sh
# fire a banner through the helper exactly as the hook would
~/.copilot/notify/bin/copilot-notify done "testing my change"
```

Please confirm a banner appears and the bundled sound plays before opening a PR.
