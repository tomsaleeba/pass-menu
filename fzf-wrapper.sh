#!/bin/bash
set -euxo pipefail
cd "$(dirname "$0")"

lastSelectionFile=$HOME/.cache/pass-menu.last
touch $lastSelectionFile

if [ "${PM_PREPOP:-}" = "off" ]; then
  fzf
else
  fzf \
    -q "$(cat $lastSelectionFile)" \
    --bind "enter:execute-silent(echo {} > $lastSelectionFile)+accept" \
    --bind "ctrl-w:backward-kill-word"
fi
