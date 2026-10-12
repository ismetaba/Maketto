#!/usr/bin/env python3
"""Print the UDID of an available simulator named exactly argv[1] on the newest iOS runtime."""
import json
import re
import subprocess
import sys

name = sys.argv[1]
devices = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                                    check=True, capture_output=True, text=True).stdout)["devices"]


def version(key):
    m = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?", key)
    return tuple(int(x or 0) for x in m.groups()) if m else (0, 0, 0)


found = sorted((version(rt), d["udid"]) for rt, ds in devices.items() if "iOS" in rt
               for d in ds if d["name"] == name and d.get("isAvailable", True))
if not found:
    sys.exit(f"no simulator named {name!r}")
print(found[-1][1])
