#!/bin/zsh
set -eu
cd "${0:A:h}"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc Source/Layout.swift Source/GeometryTests.swift -o "$test_dir/geometry"
"$test_dir/geometry"
