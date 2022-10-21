#!/bin/bash
set -euxo pipefail
cd "$(dirname "$0")"

# the fzf-wrapper.sh needs to exist because passing in params means they get
# messed up inside the pass-menu.sh script... thanks escaping
./pass-menu.sh -- ./fzf-wrapper.sh
