# Kalowave skills

Agent skills for Kalowave products. One directory per skill, each self-contained with its own `SKILL.md`, CLI, and install script.

## Skills

### [`kaloclip/`](kaloclip/) — KaloClip Open API

CLI wrapper + schema reference for the KaloClip Open API (image upload, script generation, video creation, job polling). See [`kaloclip/SKILL.md`](kaloclip/SKILL.md) for the agent-facing contract.

Install the standalone CLI:

```bash
curl -fsSL https://raw.githubusercontent.com/Kalowave/skills/main/kaloclip/install.sh | bash
```

Quick start after install:

```bash
kaloclip login               # browser device-flow: key auto-saved to ~/.kaloclip/config.env
kaloclip help                # command + topic list
kaloclip resolve <product-link>   # preferred entry point for TikTok / Kalodata URLs
```

Dev clone (for contributors):

```bash
git clone https://github.com/Kalowave/skills.git
cd skills/kaloclip
./scripts/kaloclip.sh install    # symlink into ~/.local/bin for in-place editing
```

### `kalopilot/` — coming soon

## Layout

```
skills/
├── README.md                 # this file — repo-level index
├── kaloclip/
│   ├── SKILL.md              # agent contract
│   ├── install.sh            # one-liner installer
│   └── scripts/kaloclip.sh   # the CLI
└── <future skills>/
```
