<!-- promptring:start -->
## promptring — ALWAYS notify when you are waiting on the user (mandatory)

A notifier (promptring) raises a desktop banner on the user's machine through
the Copilot CLI hooks. Those hooks already cover tool-permission prompts, MCP
elicitations, and the end of every turn — you do not act for those.

They do **not** cover the built-in `ask_user` tool. When you pause mid-turn to
ask the user to decide, choose between options, or clarify something, the CLI
emits no hookable event, so under `--yolo` the user gets **no banner** and
cannot tell you are blocked on them.

This is a **hard requirement, not a suggestion**: immediately before **every**
call to `ask_user` — or any time you stop and wait for a user decision — you
**must** first run the promptring `input` command. Never call `ask_user`
without firing it first. This applies in every session and on every OS. Run
the form that matches your shell:

- **macOS / Linux / WSL** (bash, sh, zsh):

      "$HOME/.copilot/promptring/bin/promptring.py" input 'Needs your input'

- **Windows** (PowerShell):

      python "$env:USERPROFILE\.copilot\promptring\bin\promptring.py" input 'Needs your input'

Replace the message with a short hint of what you need when it helps. The only
exceptions are tool-permission approvals and simply ending your turn —
promptring already handles both.
<!-- promptring:end -->
