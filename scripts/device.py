#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile


def load_devices():
    with tempfile.NamedTemporaryFile(suffix=".json") as device_file:
        subprocess.run(
            [
                "xcrun",
                "devicectl",
                "list",
                "devices",
                "--json-output",
                device_file.name,
                "--quiet",
            ],
            check=True,
        )
        device_file.seek(0)
        data = json.load(device_file)

    return data.get("result", {}).get("devices", [])


def device_name(device):
    return device.get("deviceProperties", {}).get("name", "")


def device_model(device):
    return device.get("hardwareProperties", {}).get("marketingName", "")


def device_id(device):
    return device.get("identifier", "")


def is_available(device):
    connection = device.get("connectionProperties", {})
    return (
        connection.get("pairingState") == "paired"
        and connection.get("tunnelState") != "unavailable"
    )


def list_devices():
    devices = sorted(
        load_devices(),
        key=lambda device: (device_name(device), device_model(device), device_id(device)),
    )
    name_width = max([len(device_name(device)) for device in devices] + [4])
    model_width = max([len(device_model(device)) for device in devices] + [5])
    for device in devices:
        state = "available" if is_available(device) else "unavailable"
        print(
            f"{device_name(device):<{name_width}}  "
            f"{device_model(device):<{model_width}}  "
            f"{device_id(device)}  "
            f"{state}"
        )


def resolve_device(selector):
    devices = [device for device in load_devices() if is_available(device)]
    matches = [
        device
        for device in devices
        if selector
        in {
            device_id(device),
            device_name(device),
            device_model(device),
        }
    ]

    if not matches:
        print(f"No available physical device matched {selector!r}", file=sys.stderr)
        print("Run `rtk make devices` to list names, models, and IDs.", file=sys.stderr)
        sys.exit(1)

    if len(matches) > 1:
        print(
            f"Physical device {selector!r} matched multiple devices; use one ID:",
            file=sys.stderr,
        )
        for device in matches:
            print(
                f"{device_name(device)}  {device_model(device)}  {device_id(device)}",
                file=sys.stderr,
            )
        sys.exit(2)

    return matches[0]


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in {"list", "resolve"}:
        print(
            "Usage: device.py list | resolve <device-name-or-model-or-id>",
            file=sys.stderr,
        )
        sys.exit(2)

    if sys.argv[1] == "list":
        list_devices()
        return

    if len(sys.argv) != 3 or not sys.argv[2].strip():
        print("Usage: device.py resolve <device-name-or-model-or-id>", file=sys.stderr)
        sys.exit(2)

    print(device_id(resolve_device(sys.argv[2].strip())))


if __name__ == "__main__":
    main()
