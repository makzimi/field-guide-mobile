#!/bin/sh
# Discover previews before tests so a newly added use case cannot be missed.
set -eu
cd "$(dirname "$0")/.."
flutter_bin="${FIELD_GUIDE_FLUTTER_BIN:-../.toolchains/flutter/bin/flutter}"
dart_bin="$(dirname "$flutter_bin")/dart"
export PUB_CACHE="${PUB_CACHE:-$PWD/.pub-cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$PWD/.config}"
export FLUTTER_SUPPRESS_ANALYTICS=true
export DASH__SUPPRESS_ANALYTICS=true
"$dart_bin" run build_runner build
exec "$flutter_bin" test --no-pub "$@"
