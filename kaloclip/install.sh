#!/usr/bin/env bash
# Install the kaloclip CLI from https://github.com/Kalowave/skills.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/Kalowave/skills/main/kaloclip/install.sh | bash
#
# Env overrides (optional):
#   KALOCLIP_REPO          default: Kalowave/skills
#   KALOCLIP_REF           default: main                 (branch, tag, or SHA)
#   KALOCLIP_INSTALL_DIR   default: $HOME/.local/bin

set -euo pipefail

REPO="${KALOCLIP_REPO:-Kalowave/skills}"
REF="${KALOCLIP_REF:-main}"
TARGET_DIR="${KALOCLIP_INSTALL_DIR:-$HOME/.local/bin}"
SOURCE_URL="https://raw.githubusercontent.com/${REPO}/${REF}/kaloclip/scripts/kaloclip.sh"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

say "Installing kaloclip"
echo "  source: $SOURCE_URL"
echo "  target: $TARGET_DIR/kaloclip"

# Dependencies.
missing=()
for dep in curl jq bash; do
  command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo
  die "missing required tool(s): ${missing[*]}

  macOS:         brew install ${missing[*]}
  Debian/Ubuntu: sudo apt install -y ${missing[*]}
  RHEL/Fedora:   sudo dnf install -y ${missing[*]}"
fi
command -v python3 >/dev/null 2>&1 || echo "  (note: python3 not found — some subcommands use it for URL array encoding; ships with macOS / most distros)"

# Download.
mkdir -p "$TARGET_DIR"
target="$TARGET_DIR/kaloclip"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
if ! curl -fsSL "$SOURCE_URL" -o "$tmp"; then
  die "failed to download $SOURCE_URL"
fi
# Sanity check — expect a bash script, not an HTML 404 page.
head -1 "$tmp" | grep -q '^#!' || die "download doesn't look like a shell script. Wrong REF or repo moved?"

mv "$tmp" "$target"
trap - EXIT
chmod +x "$target"

# Report installed version (best-effort — parse the script's top comment).
say "Installed $("$target" help 2>/dev/null | head -1)"
echo "  path: $target"
echo

# PATH guidance.
case ":$PATH:" in
  *":$TARGET_DIR:"*)
    say "$TARGET_DIR is on PATH. You're ready."
    echo
    echo "Next steps:"
    echo "  kaloclip login          # one-time: get your API key via browser"
    echo "  kaloclip help           # subcommand + help-topic list"
    ;;
  *)
    say "$TARGET_DIR is NOT on your PATH yet."
    echo
    echo "Add this to your shell config (~/.zshrc or ~/.bashrc) and reload:"
    echo
    echo "    export PATH=\"$TARGET_DIR:\$PATH\""
    echo
    echo "Then:"
    echo "  kaloclip login          # one-time: get your API key via browser"
    echo "  kaloclip help           # subcommand + help-topic list"
    ;;
esac
