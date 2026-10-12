#!/usr/bin/env python3
"""Print the UDID of the newest available iPhone simulator (for CI test runs)."""
import json
import re
import subprocess
import sys

raw = subprocess.run(
    ["xcrun", "simctl", "list", "devices", "available", "-j"],
    check=True, capture_output=True, text=True,
).stdout
devices = json.loads(raw)["devices"]


def runtime_version(key: str):
    match = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?", key)
    return tuple(int(part or 0) for part in match.groups()) if match else (0, 0, 0)


candidates = []
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    for device in entries:
        if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
            candidates.append((runtime_version(runtime), device["name"], device["udid"]))

if not candidates:
    sys.exit("No available iPhone simulator found")

candidates.sort()
version, name, udid = candidates[-1]
print(f"Using {name} (iOS {'.'.join(map(str, version))})", file=sys.stderr)
print(udid)
