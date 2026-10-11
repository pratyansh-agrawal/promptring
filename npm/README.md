# promptring

Native desktop notifications for GitHub Copilot CLI when an agent finishes,
needs input, or encounters a blocker.

## Install

```sh
npm install -g promptring
```

### Prerequisites

- Node.js 18+
- Python 3
- macOS: Xcode Command Line Tools
- Linux: `notify-send` for notification banners

The installer detects macOS, Windows, Linux, or WSL automatically and configures
the Copilot CLI hooks. Restart Copilot CLI after installation.

## Commands

```sh
promptring --check             # Test the notification
promptring --mute              # Mute the chime
promptring --unmute            # Restore the chime
promptring --tring <file>      # Use a custom sound
promptring --untring           # Restore the default sound
promptring --status            # Show the current sound configuration
promptring <category> [message]
```

Supported categories are `done`, `input`, `ready`, `blocked`, and `info`.

For setup details, customization, troubleshooting, and uninstall instructions,
see the [full documentation](https://github.com/pratyansh-agrawal/promptring#readme).

MIT License
