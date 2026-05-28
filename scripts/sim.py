#!/usr/bin/env python3
import json
import re
import subprocess
import sys


UUID_RE = re.compile(r"^[0-9A-Fa-f-]{36}$")


def load_devices():
    output = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        text=True,
    )
    data = json.loads(output)
    devices = []
    for runtime_devices in data["devices"].values():
        for device in runtime_devices:
            if device.get("isAvailable", True):
                devices.append(device)
    return devices


def list_devices():
    devices = sorted(load_devices(), key=lambda device: (device["name"], device["udid"]))
    width = max([len(device["name"]) for device in devices] + [4])
    for device in devices:
        print(f"{device['name']:<{width}}  {device['udid']}  {device['state']}")


def resolve_device(selector):
    devices = load_devices()
    matches = [
        device
        for device in devices
        if selector == device["udid"] or selector == device["name"]
    ]

    if not matches:
        matches = [
            device
            for device in devices
            if device["name"].endswith(f" - {selector}")
        ]

    if not matches:
        print(f"No simulator matched {selector!r}", file=sys.stderr)
        print("Run `rtk make sims` to list names and IDs.", file=sys.stderr)
        sys.exit(1)

    if len(matches) > 1 and not UUID_RE.match(selector):
        print(
            f"Simulator {selector!r} matched multiple devices; use one of these IDs:",
            file=sys.stderr,
        )
        width = max(len(device["name"]) for device in matches)
        for device in matches:
            print(
                f"{device['name']:<{width}}  {device['udid']}  {device['state']}",
                file=sys.stderr,
            )
        sys.exit(2)

    return matches[0]


def boot_device(selector):
    device = resolve_device(selector)
    udid = device["udid"]

    if device["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", udid], check=True)

    subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
    subprocess.run(
        ["open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", udid],
        check=True,
    )
    print(f"booted {device['name']} ({udid})")


def terminate_app_on_other_booted_devices(selector, bundle_id):
    target = resolve_device(selector)
    for device in sorted(load_devices(), key=lambda item: (item["name"], item["udid"])):
        if device["udid"] == target["udid"] or device["state"] != "Booted":
            continue

        result = subprocess.run(
            ["xcrun", "simctl", "terminate", device["udid"], bundle_id],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            print(f"terminated {bundle_id} on {device['name']} ({device['udid']})")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in {"list", "boot", "resolve", "terminate-others"}:
        print(
            "Usage: sim.py list | boot <sim-name-or-udid> | resolve <sim-name-or-udid> | terminate-others <sim-name-or-udid> <bundle-id>",
            file=sys.stderr,
        )
        sys.exit(2)

    if sys.argv[1] == "list":
        list_devices()
        return

    if sys.argv[1] == "terminate-others":
        if len(sys.argv) != 4 or not sys.argv[2].strip() or not sys.argv[3].strip():
            print("Usage: sim.py terminate-others <sim-name-or-udid> <bundle-id>", file=sys.stderr)
            sys.exit(2)
        terminate_app_on_other_booted_devices(sys.argv[2].strip(), sys.argv[3].strip())
        return

    if len(sys.argv) != 3 or not sys.argv[2].strip():
        print("Usage: rtk make sim SIM='iPhone 17'", file=sys.stderr)
        sys.exit(2)

    selector = sys.argv[2].strip()
    if sys.argv[1] == "resolve":
        print(resolve_device(selector)["udid"])
        return

    boot_device(selector)


if __name__ == "__main__":
    main()
