#!/bin/bash
# Prepares your Mac to build Dashhound. Safe to run several times: it never deletes or overwrites
# anything (your Config.xcconfig is only created if it does not exist yet). Nothing paid.
#   scripts/bootstrap.sh         # everything needed to build the app
#   scripts/bootstrap.sh --dev   # + Meta SDK samples and the Claude Code plugin (contributors)
set -euo pipefail
cd "$(dirname "$0")/.."

ok() { printf '  ✓ %s\n' "$1"; }
todo() { printf '  → %s\n' "$1"; }

echo "== Xcode"
if ! xcodebuild -version >/dev/null 2>&1; then
  todo "Xcode is missing or its license is not accepted."
  todo "Install Xcode from the App Store, open it once, then run: sudo xcodebuild -license accept"
  exit 1
fi
ok "$(xcodebuild -version | head -1)"

echo "== XcodeGen (generates the Xcode project)"
if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then
    brew install xcodegen
  else
    todo "Homebrew is missing: install it from https://brew.sh, then run this script again."
    exit 1
  fi
fi
ok "XcodeGen $(xcodegen --version | awk '{print $NF}')"

echo "== Your signing settings (Config.xcconfig)"
if [ -f Config.xcconfig ]; then
  ok "Config.xcconfig already exists (left untouched)"
else
  cp Config.example.xcconfig Config.xcconfig
  todo "Created Config.xcconfig: open it and set DASHHOUND_TEAM_ID and DASHHOUND_BUNDLE_ID (see INSTALL.md, step 6)."
fi

if [ "${1:-}" = "--dev" ]; then
  echo "== Meta SDK samples (reference only, ignored by git)"
  if [ ! -d vendor/dat ]; then
    git clone --depth 1 https://github.com/facebook/meta-wearables-dat-ios vendor/dat
  fi
  ok "vendor/dat"
  echo "== Claude Code plugin mwdat-ios (optional)"
  if command -v claude >/dev/null; then
    claude plugin marketplace add facebook/meta-wearables-dat-ios 2>/dev/null || true
    claude plugin install mwdat-ios@mwdat-ios-marketplace 2>/dev/null || todo "install it from Claude Code: /plugin"
  else
    todo "Claude Code CLI not found (optional)"
  fi
fi

echo "== Xcode project"
xcodegen generate >/dev/null
ok "Dashcam.xcodeproj generated — open it: open Dashcam.xcodeproj"
