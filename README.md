# Kalowave skills

Reusable agent skills for Kalowave products.

## kaloclip

CLI wrapper + schema reference for the KaloClip Open API. See [SKILL.md](SKILL.md) for the agent-facing contract.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/Kalowave/skills/main/install.sh | bash
```

Downloads a single self-contained shell script to `~/.local/bin/kaloclip`. Requires `bash`, `curl`, `jq` (install hint printed if missing). To install somewhere else: `KALOCLIP_INSTALL_DIR=/usr/local/bin curl ... | bash`.

### First run

```bash
kaloclip login               # one-time: browser confirms, API key auto-saved to ~/.kaloclip/config.env
kaloclip help                # command list + topic list
kaloclip help <topic>        # per-endpoint body schema + live-fetch pointers
```

### Uninstall

```bash
rm ~/.local/bin/kaloclip
rm -rf ~/.kaloclip           # removes the saved API key too
```

### For contributors (dev clone)

```bash
git clone https://github.com/Kalowave/skills.git
cd skills
./scripts/kaloclip.sh install    # symlinks into ~/.local/bin for in-place editing
```
