#!/bin/bash

# Build and package WebRTC frameworks for all supported Apple platforms.
# Generates device, simulator, Catalyst, and macOS slices and assembles a
# multi-platform XCFramework ready for distribution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_ROOT="$PROJECT_ROOT/src"
HEADERS_SOURCE="$SRC_ROOT/sdk/objc"
OUTPUT_NAME="${OUTPUT_NAME:-WebRTC.xcframework}"
export OUTPUT_NAME
OUTPUT_PATH="$SRC_ROOT/$OUTPUT_NAME"

IOS_DEVICE_TARGET="${IOS_DEVICE_TARGET:-13.0}"
IOS_SIM_TARGET="${IOS_SIM_TARGET:-13.0}"
CATALYST_TARGET="${CATALYST_TARGET:-14.0}"
MAC_TARGET="${MAC_TARGET:-11.0}"

TEMP_DIRS=()

cleanup() {
  local dirs=("${TEMP_DIRS[@]-}")
  for dir in "${dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
    fi
  done
}
trap cleanup EXIT

log () {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

run () {
  log "$*"
  "$@"
}

require_command () {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] Missing required command: $1"
    exit 1
  fi
}

require_command gn
require_command ninja
require_command xcodebuild
require_command lipo

copy_headers_tree () {
  local source="$1"
  local destination="$2"
  python3 - "$source" "$destination" <<'PY'
import os
import shutil
import sys
from pathlib import Path

src = Path(sys.argv[1]).resolve()
dst = Path(sys.argv[2]).resolve()

if not src.exists():
    sys.exit(0)

if dst.exists():
    shutil.rmtree(dst)

for root, dirs, files in os.walk(src):
    rel = Path(root).relative_to(src)
    target_dir = dst / rel
    target_dir.mkdir(parents=True, exist_ok=True)
    for name in files:
        if not name.endswith(".h"):
            continue
        shutil.copy2(Path(root) / name, target_dir / name, follow_symlinks=False)
PY
}

gn_gen_and_build () {
  local name="$1"
  local out_dir="$2"
  local target="$3"
  local args="$4"

  log "=== [$name] GN gen (${out_dir})"
  run gn gen "$out_dir" --args="$args"

  log "=== [$name] ninja build (${target})"
  run ninja -C "$out_dir" "$target"
}

sync_objc_headers () {
  local framework_path="$1"
  local destination="$framework_path/Headers/sdk/objc"

  if [[ ! -d "$HEADERS_SOURCE" ]]; then
    log "[WARN] Objective-C headers not found at $HEADERS_SOURCE; skipping sync."
    return
  fi

  log "[INFO] Syncing Objective-C headers into $(basename "$framework_path")"
  mkdir -p "$destination"
  copy_headers_tree "$HEADERS_SOURCE" "$destination"
}

rewrite_module_map () {
  local framework_path="$1"
  local module_dir="$framework_path/Modules"
  if [[ ! -d "$module_dir" ]]; then
    return
  fi
  cat > "$module_dir/module.modulemap" <<'EOF'
framework module WebRTC {
  header "WebRTC.h"
  export *
}
EOF
}

create_header_aliases () {
  local framework_path="$1"
  local headers_root="$framework_path/Headers"
  local sdk_root="$headers_root/sdk/objc"
  if [[ ! -d "$sdk_root" ]]; then
    return
  fi
  rm -rf "$headers_root/Framework"
  find "$sdk_root" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
    local name
    name=$(basename "$dir")
    if [[ "$name" == "Framework" ]]; then
      continue
    fi
    local alias_path="$headers_root/$name"
    if [[ -e "$alias_path" ]]; then
      continue
    fi
    log "   -> Mirroring sdk/objc/$name into Headers/$name"
    mkdir -p "$alias_path"
    copy_headers_tree "$dir" "$alias_path"
  done
}

create_helper_links () {
  local framework_path="$1"
  local headers_root="$framework_path/Headers"
  local helpers_root="$headers_root/helpers"
  if [[ ! -d "$helpers_root" ]]; then
    return
  fi
  python3 - "$headers_root" <<'PY'
import os
import sys

root = sys.argv[1]
helpers = os.path.join(root, "helpers")

def needs_helper_link(dirpath):
    for name in os.listdir(dirpath):
        if not name.endswith(".h"):
            continue
        path = os.path.join(dirpath, name)
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                if "helpers/" in fh.read():
                    return True
        except OSError:
            pass
    return False

for dirpath, dirnames, filenames in os.walk(root):
    if dirpath == helpers:
        continue
    if needs_helper_link(dirpath):
        link_path = os.path.join(dirpath, "helpers")
        if os.path.exists(link_path):
            continue
        rel = os.path.relpath(helpers, dirpath)
        try:
            os.symlink(rel, link_path)
        except OSError:
            pass
PY
}

prepare_framework_headers () {
  local framework_path="$1"
  sync_objc_headers "$framework_path"
  rewrite_module_map "$framework_path"
  create_header_aliases "$framework_path"
  create_helper_links "$framework_path"
}

create_universal_framework () {
  local label="$1"
  local arm_path="$2"
  local x64_path="$3"

  if [[ ! -d "$arm_path" ]]; then
    echo "[ERROR] Missing arm64 framework for $label at $arm_path"
    exit 1
  fi
  if [[ ! -d "$x64_path" ]]; then
    echo "[ERROR] Missing x86_64 framework for $label at $x64_path"
    exit 1
  fi

  local temp_dir
  temp_dir=$(mktemp -d "$SRC_ROOT/xcframework_${label}_XXXXXX")
  TEMP_DIRS+=("$temp_dir")

  local universal_path="$temp_dir/WebRTC.framework"
  log "[INFO] Creating universal $label framework"
  rsync -a "$arm_path/" "$universal_path/"
  lipo -create \
    "$arm_path/WebRTC" \
    "$x64_path/WebRTC" \
    -output "$universal_path/WebRTC"

  echo "$universal_path"
}

pushd "$SRC_ROOT" >/dev/null

gn_gen_and_build "ios-device arm64" "out_ios_arm64" "framework_objc" \
  "target_os=\"ios\" target_cpu=\"arm64\" target_environment=\"device\" ios_deployment_target=\"$IOS_DEVICE_TARGET\" is_debug=false ios_enable_code_signing=false use_lld=true enable_dsyms=true symbol_level=1 rtc_include_tests=false rtc_enable_objc_symbol_export=true rtc_enable_symbol_export=true"

gn_gen_and_build "ios-simulator arm64" "out_ios_sim_arm64" "framework_objc" \
  "target_os=\"ios\" target_cpu=\"arm64\" target_environment=\"simulator\" ios_deployment_target=\"$IOS_SIM_TARGET\" is_debug=false ios_enable_code_signing=false use_lld=true enable_dsyms=true symbol_level=1 rtc_include_tests=false rtc_enable_objc_symbol_export=true rtc_enable_symbol_export=true"

gn_gen_and_build "ios-simulator x86_64" "out_ios_sim_x64" "framework_objc" \
  "target_os=\"ios\" target_cpu=\"x64\" target_environment=\"simulator\" ios_deployment_target=\"$IOS_SIM_TARGET\" is_debug=false ios_enable_code_signing=false use_lld=true enable_dsyms=true symbol_level=1 rtc_include_tests=false rtc_enable_objc_symbol_export=true rtc_enable_symbol_export=true"

gn_gen_and_build "ios-catalyst arm64" "out_ios_catalyst_arm64" "framework_objc" \
  "target_os=\"ios\" target_cpu=\"arm64\" target_environment=\"catalyst\" ios_deployment_target=\"$CATALYST_TARGET\" is_debug=false ios_enable_code_signing=false use_lld=true enable_dsyms=true symbol_level=1 rtc_include_tests=false rtc_enable_objc_symbol_export=true rtc_enable_symbol_export=true"

gn_gen_and_build "ios-catalyst x86_64" "out_ios_catalyst_x64" "framework_objc" \
  "target_os=\"ios\" target_cpu=\"x64\" target_environment=\"catalyst\" ios_deployment_target=\"$CATALYST_TARGET\" is_debug=false ios_enable_code_signing=false use_lld=true enable_dsyms=true symbol_level=1 rtc_include_tests=false rtc_enable_objc_symbol_export=true rtc_enable_symbol_export=true"

gn_gen_and_build "macOS arm64" "out_macos_arm64" "mac_framework_objc" \
  "target_os=\"mac\" target_cpu=\"arm64\" mac_deployment_target=\"$MAC_TARGET\" is_debug=false use_lld=true enable_dsyms=true symbol_level=1 rtc_include_tests=false rtc_enable_objc_symbol_export=true rtc_enable_symbol_export=true"

gn_gen_and_build "macOS x86_64" "out_macos_x64" "mac_framework_objc" \
  "target_os=\"mac\" target_cpu=\"x64\" mac_deployment_target=\"$MAC_TARGET\" is_debug=false use_lld=true enable_dsyms=true symbol_level=1 rtc_include_tests=false rtc_enable_objc_symbol_export=true rtc_enable_symbol_export=true"

popd >/dev/null

IOS_DEVICE_FRAMEWORK="$SRC_ROOT/out_ios_arm64/WebRTC.framework"
IOS_SIM_ARM64_FRAMEWORK="$SRC_ROOT/out_ios_sim_arm64/WebRTC.framework"
IOS_SIM_X64_FRAMEWORK="$SRC_ROOT/out_ios_sim_x64/WebRTC.framework"
IOS_CATALYST_ARM64_FRAMEWORK="$SRC_ROOT/out_ios_catalyst_arm64/WebRTC.framework"
IOS_CATALYST_X64_FRAMEWORK="$SRC_ROOT/out_ios_catalyst_x64/WebRTC.framework"
MAC_ARM64_FRAMEWORK="$SRC_ROOT/out_macos_arm64/WebRTC.framework"
MAC_X64_FRAMEWORK="$SRC_ROOT/out_macos_x64/WebRTC.framework"

for required_path in \
  "$IOS_DEVICE_FRAMEWORK" \
  "$IOS_SIM_ARM64_FRAMEWORK" \
  "$IOS_SIM_X64_FRAMEWORK" \
  "$IOS_CATALYST_ARM64_FRAMEWORK" \
  "$IOS_CATALYST_X64_FRAMEWORK" \
  "$MAC_ARM64_FRAMEWORK" \
  "$MAC_X64_FRAMEWORK"
do
  if [[ ! -d "$required_path" ]]; then
    echo "[ERROR] Expected framework not found: $required_path"
    exit 1
  fi
done

SIM_UNIVERSAL_FRAMEWORK=$(create_universal_framework "simulator" "$IOS_SIM_ARM64_FRAMEWORK" "$IOS_SIM_X64_FRAMEWORK")
CATALYST_UNIVERSAL_FRAMEWORK=$(create_universal_framework "catalyst" "$IOS_CATALYST_ARM64_FRAMEWORK" "$IOS_CATALYST_X64_FRAMEWORK")
MAC_UNIVERSAL_FRAMEWORK=$(create_universal_framework "macos" "$MAC_ARM64_FRAMEWORK" "$MAC_X64_FRAMEWORK")

FRAMEWORKS_FOR_XC=(
  "$IOS_DEVICE_FRAMEWORK"
  "$SIM_UNIVERSAL_FRAMEWORK"
  "$CATALYST_UNIVERSAL_FRAMEWORK"
  "$MAC_UNIVERSAL_FRAMEWORK"
)

for framework in "${FRAMEWORKS_FOR_XC[@]}"; do
  prepare_framework_headers "$framework"
done

if [[ -d "$OUTPUT_PATH" ]]; then
  log "[INFO] Removing existing XCFramework at $OUTPUT_PATH"
  rm -rf "$OUTPUT_PATH"
fi

log "[INFO] Creating XCFramework ($OUTPUT_NAME)"
XC_ARGS=()
for framework in "${FRAMEWORKS_FOR_XC[@]}"; do
  XC_ARGS+=(-framework "$framework")
done

run xcodebuild -create-xcframework "${XC_ARGS[@]}" -output "$OUTPUT_PATH"

if [[ -d "$OUTPUT_PATH" ]]; then
  log "[OK] XCFramework created: $OUTPUT_PATH"
  log "[STATS] XCFramework slices:"
  find "$OUTPUT_PATH" -maxdepth 2 -type f -name "WebRTC" -print0 | while IFS= read -r -d '' binary; do
    log "   $(dirname "$binary")"
    lipo -info "$binary"
  done
else
  echo "[ERROR] Failed to create XCFramework"
  exit 1
fi
