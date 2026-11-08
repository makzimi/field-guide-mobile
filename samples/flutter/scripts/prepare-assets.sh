#!/bin/sh
# Generated build inputs only. Edit the canonical samples/contract files.
set -eu
workspace_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
asset_dir="$workspace_dir/apps/field_guide/assets/generated"
mkdir -p "$asset_dir"
for fixture in catalog-valid catalog-changed catalog-boundary catalog-long-text catalog-invalid-duplicate catalog-invalid-enum; do
  cp "$workspace_dir/../contract/$fixture.json" "$asset_dir/$fixture.json"
done
