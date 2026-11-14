#!/bin/sh
# The shared test command regenerates discovery. Recording is explicit.
set -eu
exec "$(dirname "$0")/test.sh" test/preview_golden_test.dart "$@"
