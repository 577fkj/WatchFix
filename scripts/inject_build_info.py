#!/usr/bin/env python3

import argparse
import plistlib
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--staging-dir", required=True)
    parser.add_argument("--short-version", required=True)
    parser.add_argument("--git-hash", required=True)
    parser.add_argument("--build-machine-os-build", required=True)
    parser.add_argument("--theos-git-hash", required=True)
    parser.add_argument("--theos-build-version", required=True)
    parser.add_argument("--platform-name", required=True)
    parser.add_argument("--sdk-version", required=True)
    parser.add_argument("--supported-platform", required=True)
    parser.add_argument("--minimum-os-version", required=True)
    parser.add_argument("--device-family", action="append", type=int, required=True)
    parser.add_argument("--required-device-capability", action="append", required=True)
    parser.add_argument("--build-type", required=True)
    parser.add_argument("--build-visibility", required=True)
    parser.add_argument("--build-variant", required=True)
    parser.add_argument("--configuration-platform", required=True)
    return parser.parse_args()


def is_internal_plugin(relative_path: Path) -> bool:
    normalized_path = f"/{relative_path.as_posix()}"
    return normalized_path.startswith("/Applications/WatchFix.app/PlugIns/")


def update_payload(payload: dict, args: argparse.Namespace, relative_path: Path) -> None:
    if not is_internal_plugin(relative_path):
        payload["CFBundleShortVersionString"] = args.short_version
        payload["CFBundleVersion"] = args.git_hash

    payload["BuildMachineOSBuild"] = args.build_machine_os_build
    payload["DTTheos"] = args.theos_git_hash
    payload["DTTheosBuild"] = args.theos_build_version
    payload["DTPlatformName"] = args.platform_name
    payload["DTSDKName"] = f"{args.platform_name}{args.sdk_version}"
    payload["DTPlatformVersion"] = args.sdk_version
    payload["CFBundleSupportedPlatforms"] = [args.supported_platform]
    payload["MinimumOSVersion"] = args.minimum_os_version
    payload["UIDeviceFamily"] = args.device_family
    payload["UIRequiredDeviceCapabilities"] = args.required_device_capability
    payload["WFConfiguration"] = (
        f"{args.build_type}-{args.build_variant}-{args.build_visibility}-{args.configuration_platform}"
    )
    payload["WFVariant"] = args.build_variant

    if "WFPluginVersion" in payload and not is_internal_plugin(relative_path):
        payload["WFPluginVersion"] = args.short_version
    if "WFPluginBuildVersion" in payload and not is_internal_plugin(relative_path):
        payload["WFPluginBuildVersion"] = args.git_hash


def main() -> None:
    args = parse_args()
    staging_dir = Path(args.staging_dir)
    updated_paths: list[str] = []

    for plist_path in sorted(staging_dir.rglob("Info.plist")):
        relative_path = plist_path.relative_to(staging_dir)
        with plist_path.open("rb") as handle:
            payload = plistlib.load(handle)

        if not isinstance(payload, dict):
            continue

        update_payload(payload, args, relative_path)

        with plist_path.open("wb") as handle:
            plistlib.dump(payload, handle, sort_keys=False)

        updated_paths.append(relative_path.as_posix())

    if updated_paths:
        print("Injected build info into:")
        for updated_path in updated_paths:
            print(updated_path)


if __name__ == "__main__":
    main()
