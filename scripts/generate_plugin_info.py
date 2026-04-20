#!/usr/bin/env python3
import argparse
import plistlib
from pathlib import Path
from typing import Optional
from uuid import UUID


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--plugin-name", required=True)
    parser.add_argument("--plugin-kind", required=True, choices=["tweak", "bundle_with_tool"])
    parser.add_argument("--package-scheme", required=True)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--minimum-os-version", default="15.0")
    parser.add_argument("--plugin-short-version", required=True)
    parser.add_argument("--plugin-version", required=True)
    return parser.parse_args()


def require_string(mapping: dict, key: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise RuntimeError(f"{key} must be a non-empty string")
    return value.strip()


def require_integer(mapping: dict, key: str) -> int:
    value = mapping.get(key)
    if not isinstance(value, int):
        raise RuntimeError(f"{key} must be an integer")
    return value


def require_boolean(mapping: dict, key: str, default: Optional[bool] = None) -> bool:
    value = mapping.get(key, default)
    if not isinstance(value, bool):
        raise RuntimeError(f"{key} must be a boolean")
    return value


def require_string_list(mapping: dict, key: str) -> list[str]:
    values = mapping.get(key)
    if not isinstance(values, list):
        raise RuntimeError(f"{key} must be an array")

    normalized: list[str] = []
    for value in values:
        if not isinstance(value, str) or not value.strip():
            raise RuntimeError(f"{key} must only contain non-empty strings")
        normalized.append(value.strip())
    return normalized


def normalize_capability_list(mapping: dict, key: str) -> list[str]:
    normalized: list[str] = []
    for value in require_string_list(mapping, key):
        try:
            normalized.append(str(UUID(value)).upper())
        except ValueError as exc:
            raise RuntimeError(f"{key} contains an invalid UUID: {value}") from exc
    return normalized


def normalize_plugin_version(manifest: dict) -> str:
    version_dict = {}
    if "WFPluginMinimumSystemVersion" in manifest:
        version_dict["WFPluginMinimumSystemVersion"] = require_integer(manifest, "WFPluginMinimumSystemVersion")
    if "WFPluginMaximumSystemVersion" in manifest:
        version_dict["WFPluginMaximumSystemVersion"] = require_integer(manifest, "WFPluginMaximumSystemVersion")
    if "WFPluginMinimumWatchOSVersion" in manifest:
        version_dict["WFPluginMinimumWatchOSVersion"] = require_integer(manifest, "WFPluginMinimumWatchOSVersion")
    if "WFPluginMaximumWatchOSVersion" in manifest:
        version_dict["WFPluginMaximumWatchOSVersion"] = require_integer(manifest, "WFPluginMaximumWatchOSVersion")
    return version_dict


def normalize_plugin_manifest(manifest: dict) -> dict:
    if not isinstance(manifest, dict):
        raise RuntimeError("WFPluginManifest must be a dictionary")

    normalized = { # required keys
        "WFPluginTitle": require_string(manifest, "WFPluginTitle"),
        "WFPluginDetail": require_string(manifest, "WFPluginDetail"),
        "WFPluginScopeIdentifier": require_string(manifest, "WFPluginScopeIdentifier"),
        "WFPluginHasInstallableContent": require_boolean(manifest, "WFPluginHasInstallableContent"),
        "WFPluginRestartExecutables": require_string_list(manifest, "WFPluginRestartExecutables"),
    }

    version_info = normalize_plugin_version(manifest)
    normalized.update(version_info)

    injection_targets = manifest.get("WFPluginInjectionTargets")
    if not isinstance(injection_targets, dict):
        raise RuntimeError("WFPluginInjectionTargets must be a dictionary")
    normalized["WFPluginInjectionTargets"] = {
        "Bundles": require_string_list(injection_targets, "Bundles"),
        "Executables": require_string_list(injection_targets, "Executables"),
    }

    if "WFPluginPresentAsTool" in manifest:
        normalized["WFPluginPresentAsTool"] = require_boolean(manifest, "WFPluginPresentAsTool")

    if "WFPluginConfigurationClass" in manifest:
        normalized["WFPluginConfigurationClass"] = require_string(manifest, "WFPluginConfigurationClass")

    if "WFPluginNanoCapabilities" in manifest:
        normalized["WFPluginNanoCapabilities"] = normalize_capability_list(manifest, "WFPluginNanoCapabilities")

    if "WFPluginNanoCapabilitiesAnyPredicate" in manifest:
        normalized["WFPluginNanoCapabilitiesAnyPredicate"] = require_boolean(
            manifest,
            "WFPluginNanoCapabilitiesAnyPredicate",
        )
    
    if "WFPluginOSRestrictions" in manifest:
        os_restrictions = manifest["WFPluginOSRestrictions"]
        if not isinstance(os_restrictions, list):
            raise RuntimeError("WFPluginOSRestrictions must be an array")
        normalized_restrictions: list[dict] = []
        for item in os_restrictions:
            if not isinstance(item, dict):
                raise RuntimeError("WFPluginOSRestrictions must only contain dictionaries")
            normalized_restrictions.append(normalize_plugin_version(item))
        normalized["WFPluginOSRestrictions"] = normalized_restrictions

    return normalized


def generated_install_artifacts(args: argparse.Namespace, plugin_manifest: dict) -> list[dict]:
    if not plugin_manifest["WFPluginHasInstallableContent"]:
        return []

    if args.plugin_kind == "bundle_with_tool":
        return [
            {
                "source": f"Payload/{args.plugin_name}.bundle",
                "target": f"{args.plugin_name}.bundle",
                "destination": "/Library/ControlCenter/Bundles",
                "type": "directory",
            }
        ]

    dylib_name = f"{args.plugin_name}.dylib"
    return [
        {
            "source": dylib_name,
            "target": dylib_name,
            "destination": "/Library/MobileSubstrate/DynamicLibraries",
            "type": "file",
        },
    ]


def main() -> None:
    args = parse_args()
    manifest_path = Path(args.manifest)
    output_path = Path(args.output)

    with manifest_path.open("rb") as handle:
        manifest = plistlib.load(handle)

    plugin_manifest = manifest.get("WFPluginManifest")
    if not isinstance(plugin_manifest, dict):
        raise RuntimeError("manifest.plist must contain WFPluginManifest")
    plugin_manifest = normalize_plugin_manifest(plugin_manifest)

    payload = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": args.executable,
        "CFBundleIdentifier": f"cn.fkj233.watchfix.plugin.{args.plugin_name}",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": args.plugin_name,
        "CFBundlePackageType": "BNDL",
        "CFBundleShortVersionString": args.plugin_short_version,
        "CFBundleVersion": args.plugin_version,
        "MinimumOSVersion": args.minimum_os_version,
        "WFBuildType": "WatchFix",
        "WFPluginVersion": args.plugin_short_version,
        "WFPluginBuildVersion": args.plugin_version,
        "WFPluginManifest": plugin_manifest,
        "WFInstallArtifacts": generated_install_artifacts(args, plugin_manifest),
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as handle:
        plistlib.dump(payload, handle, sort_keys=False)


if __name__ == "__main__":
    main()
