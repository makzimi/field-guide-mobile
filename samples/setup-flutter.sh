#!/bin/sh
# Restore the exact public Flutter SDK used for the Field Guide samples.
set -eu

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo 'This pinned SDK archive is for macOS arm64.' >&2
  exit 1
fi

samples_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cache_dir="$samples_dir/.toolchains"
archive="$cache_dir/flutter_macos_arm64_3.47.7-stable.zip"
sdk="$cache_dir/flutter"
url='https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.7-stable.zip'
expected='dd9da574c3168460550117eb0e8dd0313ae934fabf64a82a6d557fff5fd1422e'
expected_size=2263893135
expected_revision='abaf9c523780a608bd46686fd5e53740a07077f8'

if [ -x "$sdk/bin/flutter" ]; then
  actual_revision=$(git -C "$sdk" rev-parse HEAD 2>/dev/null || true)
  if [ "$actual_revision" = "$expected_revision" ]; then
    echo "Verified existing Flutter SDK at $sdk ($actual_revision)"
    exit 0
  fi
  echo "Existing Flutter SDK has unexpected revision: $actual_revision" >&2
  exit 1
fi

mkdir -p "$cache_dir"
if [ -f "$archive" ]; then
  current_size=$(wc -c < "$archive" | tr -d ' ')
else
  current_size=0
fi
if [ "$current_size" -lt "$expected_size" ]; then
  curl -fL --retry 3 -C - "$url" -o "$archive"
fi
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
if [ "$actual" != "$expected" ]; then
  echo "Flutter archive checksum mismatch: $actual" >&2
  exit 1
fi

if [ ! -x "$sdk/bin/flutter" ]; then
  unzip -q "$archive" -d "$cache_dir"
fi

if [ ! -x "$sdk/bin/flutter" ]; then
  echo 'Flutter SDK executable was not found after extraction.' >&2
  exit 1
fi

echo "Verified Flutter SDK at $sdk"
echo "Run: $sdk/bin/flutter --version"
