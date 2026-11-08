#!/bin/sh
# Checks the journal's core (crypto, merging, streaks, sun times) on the Mac,
# and the whole account and sync cycle against the live server with a
# throwaway account it deletes afterwards. No simulator needed.
set -e
cd "$(dirname "$0")/.."
out=$(mktemp -d)
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} xcrun swiftc -O -o "$out/checks" \
  Tekkoh/Core/Crypto.swift Tekkoh/Core/Models.swift Tekkoh/Core/API.swift Tekkoh/Core/Keychain.swift Tekkoh/Core/SunTimes.swift Checks/main.swift
"$out/checks"
