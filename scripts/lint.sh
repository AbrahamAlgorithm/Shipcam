#!/bin/sh
# Checks formatting and code quality without changing any file. CI runs this too.
set -eu
cd "$(dirname "$0")/.."

swift format lint --strict --recursive --parallel \
    App Packages/ShipcamKit/Package.swift Packages/ShipcamKit/Sources Packages/ShipcamKit/Tests
swiftlint lint --strict --quiet
