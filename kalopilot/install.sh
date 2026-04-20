#!/usr/bin/env bash
# Install the kalopilot CLI from https://github.com/Kalowave/skills.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/Kalowave/skills/main/kalopilot/install.sh | bash
#
# Env overrides (optional):
#   KALOPILOT_REPO          default: Kalowave/skills
#   KALOPILOT_REF           default: main                 (branch, tag, or SHA)
#   KALOPILOT_INSTALL_DIR   default: $HOME/.local/bin

set -euo pipefail

REPO="${KALOPILOT_REPO:-Kalowave/skills}"
REF="${KALOPILOT_REF:-main}"
TARGET_DIR="${KALOPILOT_INSTALL_DIR:-$HOME/.local/bin}"
SOURCE_URL="https://raw.githubusercontent.com/${REPO}/${REF}/kalopilot/scripts/pilot.sh"
TOKEN_DIR="$HOME/.kalopilot"
TOKEN_FILE="$TOKEN_DIR/token"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

say "Installing kalopilot"
echo "  source: $SOURCE_URL"
echo "  target: $TARGET_DIR/kalopilot"

# Dependencies — pilot.sh only needs bash + curl.
missing=()
for dep in bash curl; do
  command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo
  die "missing required tool(s): ${missing[*]}

  macOS:         brew install ${missing[*]}
  Debian/Ubuntu: sudo apt install -y ${missing[*]}
  RHEL/Fedora:   sudo dnf install -y ${missing[*]}"
fi

# Download.
mkdir -p "$TARGET_DIR"
target="$TARGET_DIR/kalopilot"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
if ! curl -fsSL "$SOURCE_URL" -o "$tmp"; then
  die "failed to download $SOURCE_URL"
fi
head -1 "$tmp" | grep -q '^#!' || die "download doesn't look like a shell script. Wrong REF or repo moved?"

mv "$tmp" "$target"
trap - EXIT
chmod +x "$target"
say "Installed at $target"
echo

# PATH guidance.
case ":$PATH:" in
  *":$TARGET_DIR:"*)
    say "$TARGET_DIR is on PATH."
    ;;
  *)
    say "$TARGET_DIR is NOT on your PATH yet."
    echo
    echo "Add this to your shell config (~/.zshrc or ~/.bashrc) and reload:"
    echo
    echo "    export PATH=\"$TARGET_DIR:\$PATH\""
    ;;
esac

# Token guidance — pilot.sh refuses to run without one.
echo
if [ -f "$TOKEN_FILE" ]; then
  say "Token already saved at $TOKEN_FILE."
else
  say "Next step: save your KaloData token (pilot.sh refuses to run without it)."
  echo
  echo "    mkdir -p $TOKEN_DIR && echo -n 'YOUR_TOKEN' > $TOKEN_FILE && chmod 600 $TOKEN_FILE"
  echo
  echo "Then try:"
  echo
  echo "    kalopilot query '美国热门商品有哪些？'"
  echo "    kalopilot status    # poll while it runs (1–10 min)"
  echo "    kalopilot result    # fetch the answer"
fi
