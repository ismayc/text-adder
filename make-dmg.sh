#!/bin/zsh
# Build TextAdder.app and package it as a drag-to-Applications DMG.
set -euo pipefail
cd "$(dirname "$0")"

./make-app.sh

STAGING=$(mktemp -d)
cp -R TextAdder.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f TextAdder.dmg
hdiutil create -volname "TextAdder" -srcfolder "$STAGING" -ov -format UDZO \
    TextAdder.dmg
rm -rf "$STAGING"

echo "Built TextAdder.dmg — open it and drag TextAdder to Applications."
echo "Note: the app is ad-hoc signed; after downloading, right-click > Open"
echo "the first time to get past Gatekeeper."
