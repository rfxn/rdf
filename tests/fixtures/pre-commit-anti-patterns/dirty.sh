#!/usr/bin/env bash
# Fixture: each line triggers one anti-pattern class
set -euo pipefail

sha256sum /etc/hostname                      # bare-coreutils-no-prefix (no 'command' prefix)
_tmp="/tmp/work.$$"                          # tmp-file-with-pid
_out="$(ls /etc 2>/dev/null)"               # suppression-no-comment (no same-line #)
# replaces old stub                          # tombstone-phrases
local _result="$(some_func)"               # local-rc-mask
