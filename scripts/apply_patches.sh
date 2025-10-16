#!/bin/bash

# Apply AAC patches to WebRTC source code
# Usage: ./apply_patches.sh [--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCHES_DIR="$PROJECT_ROOT/patches"
SRC_DIR="$PROJECT_ROOT/src"

FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--force]" >&2
      exit 1
      ;;
  esac
done

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

# Check if WebRTC source exists
if [[ ! -d "$SRC_DIR/.git" ]]; then
  echo "[ERROR] WebRTC source not found at $SRC_DIR" >&2
  echo "Run ./scripts/sync_webrtc.sh first" >&2
  exit 1
fi

cd "$SRC_DIR"

# Check for existing AAC files
if [[ -d "api/audio_codecs/aac" ]] && [[ "$FORCE" == "false" ]]; then
  log "[WARNING] AAC files already exist. Use --force to re-apply patches."
  exit 0
fi

log "Applying AAC patches..."

# Apply modification patches
log "  [1/4] Applying BUILD.gn modifications..."
if git apply --check "$PATCHES_DIR/0001-add-aac-to-build.patch" 2>/dev/null; then
  git apply "$PATCHES_DIR/0001-add-aac-to-build.patch"
  log "  ✓ BUILD.gn patch applied"
else
  log "  ⚠ BUILD.gn patch failed or already applied"
fi

log "  [2/4] Applying decoder factory modifications..."
if git apply --check "$PATCHES_DIR/0002-register-aac-decoder.patch" 2>/dev/null; then
  git apply "$PATCHES_DIR/0002-register-aac-decoder.patch"
  log "  ✓ Decoder factory patch applied"
else
  log "  ⚠ Decoder factory patch failed or already applied"
fi

# Extract AAC source files
log "  [3/4] Extracting AAC source files..."
cd "$PROJECT_ROOT"
tar xzf "$PATCHES_DIR/aac-source-files.tar.gz" -C "$SRC_DIR/"
log "  ✓ AAC source files extracted"

# Verify installation
log "  [4/4] Verifying installation..."
REQUIRED_FILES=(
  "$SRC_DIR/api/audio_codecs/aac/BUILD.gn"
  "$SRC_DIR/api/audio_codecs/aac/audio_decoder_aac.h"
  "$SRC_DIR/modules/audio_coding/codecs/aac/BUILD.gn"
  "$SRC_DIR/modules/audio_coding/codecs/aac/aac_format.h"
)

ALL_OK=true
for file in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    log "  ✗ Missing: $file"
    ALL_OK=false
  fi
done

if [[ "$ALL_OK" == "true" ]]; then
  log "✓ All AAC patches applied successfully!"

  # Detect milestone
  MILESTONE=$("$SCRIPT_DIR/detect_milestone.sh" "$SRC_DIR" || echo "unknown")
  log "WebRTC Milestone: $MILESTONE"
  log ""
  log "Next step: Build XCFramework with ./scripts/build_all_configs.sh"
else
  log "✗ Some patches failed to apply. Please check manually."
  exit 1
fi
