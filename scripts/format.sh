#!/bin/sh
# Rewrites Swift files to match the project style. Run it before committing.
# swift-format runs last, so layout always ends up the way it decides.
set -eu
cd "$(dirname "$0")/.."

swiftlint lint --fix --quiet
swift format --in-place --recursive --parallel \
    Packages/ShipcamKit/Package.swift Packages/ShipcamKit/Sources Packages/ShipcamKit/Tests
