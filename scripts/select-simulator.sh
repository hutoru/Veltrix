#!/usr/bin/env bash
set -euo pipefail

pick() {
  xcrun simctl list devices available --json | python3 -c '
import json
import sys

choices = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(map(int, runtime.split(".iOS-")[-1].split("-")))
    if version[0] < 16:
        continue
    for device in devices:
        name = device["name"]
        if device.get("isAvailable") and name.startswith("iPhone"):
            choices.append(("XS" in name, version, "Pro" not in name and "Max" not in name, name, device["udid"]))
if choices:
    print(max(choices)[-1])
'
}

device="$(pick)"
if [[ -z "$device" ]]; then
  xcodebuild -downloadPlatform iOS >&2
  device="$(pick)"
fi

if [[ -z "$device" ]]; then
  xcrun simctl list >&2
  echo "No compatible iPhone simulator is available" >&2
  exit 1
fi

printf '%s\n' "$device"
