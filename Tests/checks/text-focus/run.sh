#!/bin/bash
# TextFocus (Sources/StreamProtocol/TextFocus.swift): which focused element takes text, kind 64's JSON,
# and the hello's `textFocus`, compiled with the rest of StreamProtocol.
#   Tests/checks/text-focus/run.sh   compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
"$out/check"
