#!/usr/bin/env python3
"""Select a separate QA iPhone 15 Pro Max on installed iOS 26+; never download runtimes."""
import json
import os
import re
import subprocess
import sys

DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max"
NAME = "Ninho QA iPhone 15 Pro Max"


def version(runtime):
    return tuple(int(piece) for piece in re.findall(r"\d+", runtime.get("version", "0")))


def select(inventory, override=""):
    runtimes = {item["identifier"]: item for item in inventory["runtimes"]
                if item.get("isAvailable") and ".iOS-" in item["identifier"] and version(item) >= (26,)}
    for runtime_id, devices in inventory["devices"].items():
        for device in devices:
            if override and device["udid"] == override:
                if (runtime_id not in runtimes or not device.get("isAvailable") or
                        device.get("deviceTypeIdentifier") != DEVICE_TYPE):
                    raise ValueError("NINHO_SIMULATOR_UDID precisa ser um iPhone 15 Pro Max disponível com iOS 26+.")
                return device["udid"], None
    if override:
        raise ValueError("NINHO_SIMULATOR_UDID não existe neste Mac.")
    if not runtimes:
        raise ValueError("Instale um runtime iOS 26+ no Xcode; este script não baixa componentes automaticamente.")
    runtime = max(runtimes.values(), key=version)["identifier"]
    for device in inventory["devices"].get(runtime, []):
        if device.get("isAvailable") and device.get("name") == NAME and device.get("deviceTypeIdentifier") == DEVICE_TYPE:
            return device["udid"], None
    return None, runtime


def main():
    inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "--json"], text=True))
    device, runtime = select(inventory, os.environ.get("NINHO_SIMULATOR_UDID", ""))
    if device is None:
        device = subprocess.check_output(["xcrun", "simctl", "create", NAME, DEVICE_TYPE, runtime], text=True).strip()
        print(f"Simulador de QA criado: {device}", file=sys.stderr)
    print(device)


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error)) from error
