#!/bin/zsh
# Build, copy to ~/Applications, start now and at every login.
set -e
cd "${0:A:h}"
./build.sh
mkdir -p ~/Applications
pkill -x CCUsageBar || true
rm -rf ~/Applications/CCUsageBar.app && cp -R CCUsageBar.app ~/Applications/
osascript -e 'tell application "System Events" to delete (every login item whose name is "CCUsageBar")' \
          -e 'tell application "System Events" to make login item at end with properties {path:"'$HOME'/Applications/CCUsageBar.app", hidden:true}' >/dev/null
open ~/Applications/CCUsageBar.app
echo "installed; runs at login"
