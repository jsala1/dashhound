#!/bin/bash
# Prépare la machine pour Claude Code. Idempotent. Rien de payant.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Xcode"
xcodebuild -version | head -2
xcode-select -p

echo "== XcodeGen"
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || { echo "Homebrew absent : https://brew.sh"; exit 1; }
  brew install xcodegen
fi
xcodegen --version

echo "== SDK Meta DAT (samples + skills, référence locale, gitignoré)"
if [ ! -d vendor/dat ]; then
  git clone --depth 1 https://github.com/facebook/meta-wearables-dat-ios vendor/dat   # main = samples + plugin ; le SDK binaire vient du tag 1.0.0 via SPM
fi
ls vendor/dat/samples

echo "== Plugin Claude Code officiel Meta (skills DAT + MCP docs)"
if command -v claude >/dev/null; then
  claude plugin marketplace add facebook/meta-wearables-dat-ios 2>/dev/null || true
  claude plugin install mwdat-ios@mwdat-ios-marketplace 2>/dev/null || echo "(plugin déjà installé ou à installer depuis Claude Code : /plugin)"
else
  echo "CLI claude absente — installer le plugin depuis Claude Code : /plugin marketplace add facebook/meta-wearables-dat-ios"
fi

echo "== iPhone connu de Xcode"
xcrun devicectl list devices || true

echo "== Génération du projet"
xcodegen generate
echo "OK — ouvrir Dashcam.xcodeproj ou builder : xcodebuild -scheme Dashcam -destination 'generic/platform=iOS' build"
