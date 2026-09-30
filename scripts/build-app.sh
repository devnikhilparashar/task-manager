#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
swift build -c "$configuration" --package-path "$repo_dir"

binary_dir="$(swift build -c "$configuration" --package-path "$repo_dir" --show-bin-path)"
app_dir="$repo_dir/.build/AmbiantMemory.app"
signing_identity="${AMBIANT_MEMORY_SIGNING_IDENTITY:--}"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/AmbiantMemory" "$app_dir/Contents/MacOS/AmbiantMemory"
cp "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign "$signing_identity" "$app_dir"
if [[ "$signing_identity" == "-" ]]; then
  echo "Warning: ad-hoc signing can invalidate Accessibility permission after each rebuild. Remove and re-add this app in Privacy & Security > Accessibility." >&2
fi
echo "$app_dir"
