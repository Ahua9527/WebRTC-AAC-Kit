#!/bin/bash

# Sync WebRTC source code to a specific milestone
# Usage: ./sync_webrtc.sh [--milestone M143]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MILESTONE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --milestone)
      MILESTONE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--milestone M143]" >&2
      exit 1
      ;;
  esac
done

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

# Ensure depot_tools is available
if ! command -v gclient >/dev/null 2>&1; then
  echo "[ERROR] gclient not found. Please add depot_tools to PATH:" >&2
  echo "  export PATH=\"/path/to/depot_tools:\$PATH\"" >&2
  exit 1
fi

cd "$PROJECT_ROOT"

# Check if .gclient exists
if [[ ! -f .gclient ]]; then
  log "[ERROR] .gclient not found. Project not initialized properly."
  exit 1
fi

# Backup current state if src/ exists
if [[ -d src/.git ]]; then
  log "Backing up current WebRTC state..."
  CURRENT_MILESTONE=$("$SCRIPT_DIR/detect_milestone.sh" src || echo "unknown")
  log "Current milestone: $CURRENT_MILESTONE"

  # Check for uncommitted changes
  cd src
  if ! git diff --quiet || ! git diff --cached --quiet; then
    log "[WARNING] Uncommitted changes detected in src/"
    log "Please commit or stash changes before syncing."
    exit 1
  fi
  cd ..
fi

# Perform gclient sync
if [[ -z "$MILESTONE" ]]; then
  log "Syncing to latest WebRTC main branch..."
  gclient sync --force
else
  log "Syncing to WebRTC $MILESTONE..."

  # Try to find the corresponding branch or commit
  # For simplicity, we sync main first, then try to checkout milestone branch
  gclient sync --force

  cd src

  # Look for branch-heads matching the milestone
  # This is a heuristic and may need adjustment
  MILESTONE_NUM=$(echo "$MILESTONE" | grep -oE '[0-9]+')

  # Try to find a branch-heads that might correspond
  BRANCHES=$(git branch -r | grep "branch-heads/" | grep -E "[0-9]+$" || echo "")

  if [[ -n "$BRANCHES" ]]; then
    log "Available branch-heads found. Manual checkout may be needed."
    log "Run: cd src && git checkout branch-heads/XXXX"
  fi

  cd ..
fi

# Detect synchronized milestone
NEW_MILESTONE=$("$SCRIPT_DIR/detect_milestone.sh" src || echo "unknown")
log "Synchronized to milestone: $NEW_MILESTONE"

log "WebRTC sync complete!"
log "Next step: Apply AAC patches with ./scripts/apply_patches.sh"
