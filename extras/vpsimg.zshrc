# ── VPS Image Upload Helper ─────────────────────────────────
# Add this to your Mac's ~/.zshrc (or ~/.bashrc)
#
# SETUP: Change VPS_HOST to your Tailscale hostname or IP
# ────────────────────────────────────────────────────────────

VPS_HOST="gonza@100.x.x.x"  # ← change to your Tailscale IP or hostname
VPS_IMAGES_DIR="~/images"

# Upload image to VPS
# Usage:
#   vpsimg screenshot.png                     → uploads to ~/images/
#   vpsimg screenshot.png klyra-feat-auth     → uploads directly to the worktree
vpsimg() {
  local file="$1"
  local session="${2:-}"

  if [ -z "$file" ]; then
    echo "Usage: vpsimg <file> [session-name]"
    echo "  vpsimg ~/Desktop/screenshot.png"
    echo "  vpsimg ~/Desktop/mockup.png klyra-feat-auth"
    return 1
  fi

  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file"
    return 1
  fi

  local filename
  filename=$(basename "$file")

  if [ -n "$session" ]; then
    # Upload directly to the session's worktree
    # Get worktree path from dev CLI on VPS
    local worktree_path
    worktree_path=$(ssh "$VPS_HOST" "jq -r 'to_entries[] | select(.key | contains(\"$session\")) | .value.path' ~/.config/dev-cli/ports.json" 2>/dev/null)

    if [ -z "$worktree_path" ] || [ "$worktree_path" = "null" ]; then
      echo "Error: Session '$session' not found. Uploading to ~/images/ instead."
      scp "$file" "$VPS_HOST:$VPS_IMAGES_DIR/$filename"
      echo "✓ Uploaded to $VPS_IMAGES_DIR/$filename"
      echo "$VPS_IMAGES_DIR/$filename" | pbcopy
    else
      scp "$file" "$VPS_HOST:$worktree_path/$filename"
      echo "✓ Uploaded to $worktree_path/$filename"
      echo "./$filename" | pbcopy
    fi
  else
    # Upload to images dir
    ssh "$VPS_HOST" "mkdir -p $VPS_IMAGES_DIR" 2>/dev/null
    scp "$file" "$VPS_HOST:$VPS_IMAGES_DIR/$filename"
    echo "✓ Uploaded to $VPS_IMAGES_DIR/$filename"
    echo "$VPS_IMAGES_DIR/$filename" | pbcopy
  fi

  echo "  Path copied to clipboard — paste into Claude Code"
}

# Upload from clipboard (screenshot)
# Takes a screenshot-from-clipboard and uploads it
# Usage: vpsclip [session-name]
vpsclip() {
  local session="${1:-}"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local tmpfile="/tmp/clipboard-$timestamp.png"

  # Save clipboard image to temp file (macOS)
  if ! pngpaste "$tmpfile" 2>/dev/null; then
    # Fallback: try osascript
    osascript -e 'try
      set imgData to the clipboard as «class PNGf»
      set fp to open for access POSIX file "'"$tmpfile"'" with write permission
      write imgData to fp
      close access fp
    on error
      return "no image"
    end try' 2>/dev/null

    if [ ! -f "$tmpfile" ] || [ "$(cat "$tmpfile" 2>/dev/null)" = "no image" ]; then
      echo "Error: No image in clipboard. Copy an image first (Cmd+Shift+4, etc.)"
      rm -f "$tmpfile"
      return 1
    fi
  fi

  echo "✓ Clipboard image saved ($timestamp)"
  vpsimg "$tmpfile" "$session"
  rm -f "$tmpfile"
}

# Quick alias
alias vi="vpsimg"
alias vc="vpsclip"
