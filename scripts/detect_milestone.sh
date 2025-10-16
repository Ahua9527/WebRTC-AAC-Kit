#!/bin/bash

# Detect WebRTC Milestone version from source code
# Usage: ./detect_milestone.sh [src_directory]

set -euo pipefail

SRC_DIR="${1:-src}"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  echo "[ERROR] WebRTC source directory not found or not a git repository: $SRC_DIR" >&2
  exit 1
fi

cd "$SRC_DIR"

# Method 1: Check for [Mxxx] markers in recent commit messages
MILESTONE=$(git log --oneline --all --grep='^\[M[0-9]\+\]' --format='%s' | \
  grep -oE '^\[M[0-9]+\]' | \
  head -1 | \
  tr -d '[]' || echo "")

if [[ -n "$MILESTONE" ]]; then
  echo "$MILESTONE"
  exit 0
fi

# Method 2: Check branch-heads that contain current HEAD
BRANCH_HEAD=$(git branch -r --contains HEAD | \
  grep 'branch-heads/' | \
  grep -oE '[0-9]+$' | \
  sort -n | \
  tail -1 || echo "")

if [[ -n "$BRANCH_HEAD" && "$BRANCH_HEAD" -gt 7000 ]]; then
  # branch-heads numbers > 7000 are likely internal build numbers
  # Try to map to milestone (this is a heuristic)
  # M142 ≈ branch-heads/7464, M141 ≈ 7390
  # Rough formula: M = (branch_head - 7300) / 10 + 140
  MILESTONE_NUM=$(( (BRANCH_HEAD - 7300) / 10 + 140 ))
  echo "M${MILESTONE_NUM}"
  exit 0
fi

# Method 3: Check DEPS file for chromium_revision and estimate
CHROMIUM_REV=$(grep "chromium_revision" DEPS | head -1 | grep -oE '[0-9a-f]{40}' || echo "")
if [[ -n "$CHROMIUM_REV" ]]; then
  # Fallback: use commit date to estimate milestone
  COMMIT_DATE=$(git log -1 --format='%ci' 2>/dev/null | cut -d' ' -f1 || echo "")
  if [[ -n "$COMMIT_DATE" ]]; then
    YEAR=$(echo "$COMMIT_DATE" | cut -d'-' -f1)
    MONTH=$(echo "$COMMIT_DATE" | cut -d'-' -f2)

    # Rough milestone estimation based on date
    # Chrome releases ~6 weeks apart, M100 was in March 2022
    # M142 is around October 2024
    if [[ "$YEAR" == "2024" ]]; then
      case "$MONTH" in
        10|11|12) echo "M142" ;;
        07|08|09) echo "M141" ;;
        04|05|06) echo "M140" ;;
        01|02|03) echo "M139" ;;
        *) echo "M142" ;;
      esac
      exit 0
    elif [[ "$YEAR" == "2025" ]]; then
      case "$MONTH" in
        10|11|12) echo "M146" ;;
        07|08|09) echo "M145" ;;
        04|05|06) echo "M144" ;;
        01|02|03) echo "M143" ;;
        *) echo "M143" ;;
      esac
      exit 0
    fi
  fi
fi

# Fallback: unknown
echo "M142"  # Default to current known version
exit 0
