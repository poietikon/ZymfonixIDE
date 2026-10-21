#!/usr/bin/env python3
"""Check a final Code OSS product.json for Zymfonix IDE invariants.

Usage: check-product.py PRODUCT_JSON

Run on the prepared source tree (post-prepare.sh) and again on every built
application. Fails if branding is wrong, an identifier collides with VS Code,
Code - OSS or VSCodium, an update endpoint is configured, or anything points
at the Visual Studio Marketplace or VSCodium.
"""

import json
import sys

EXPECTED = {
    "nameShort": "Zymfonix IDE",
    "nameLong": "Zymfonix IDE",
    "applicationName": "zymfonix-ide",
    "dataFolderName": ".zymfonix-ide",
    "urlProtocol": "zymfonix-ide",
    "darwinBundleIdentifier": "com.zymfonix.ide",
    "linuxIconName": "zymfonix-ide",
    "linuxDesktopName": "zymfonix-ide",
    "quality": "stable",
}

# Identifiers used by Visual Studio Code, Code - OSS and VSCodium (stable and
# insiders). Zymfonix IDE must not share any of them, so it can be installed
# next to those editors without sharing settings, extensions or URL handlers.
TAKEN = {
    "applicationName": {"code", "code-insiders", "code-oss", "codium", "codium-insiders"},
    "dataFolderName": {".vscode", ".vscode-insiders", ".vscode-oss", ".vscodium", ".vscodium-insiders"},
    "sharedDataFolderName": {".vscode-shared", ".vscode-oss-shared"},
    "serverDataFolderName": {".vscode-server", ".vscode-server-insiders", ".vscode-server-oss", ".vscodium-server", ".vscodium-server-insiders"},
    "urlProtocol": {"vscode", "vscode-insiders", "code-oss", "vscodium", "vscodium-insiders"},
    "darwinBundleIdentifier": {"com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.visualstudio.code.oss", "com.vscodium", "com.vscodium.VSCodiumInsiders"},
    "linuxIconName": {"code", "vscode", "code-oss", "vscodium", "vscodium-insiders"},
    "linuxDesktopName": {"code", "code-oss", "com.visualstudio.CodeOSS", "com.visualstudio.code", "codium"},
    "nameShort": {"Code", "Code - OSS", "VSCodium", "Visual Studio Code"},
}

FORBIDDEN_KEYS = ["updateUrl"]
FORBIDDEN_TEXT = ["marketplace.visualstudio.com", "vscodium", "vscode-update.azurewebsites.net", "update.code.visualstudio.com"]
# Image hosts allowed for badges in extension READMEs; not an extension source.
TEXT_CHECK_EXEMPT = (".extensionAllowedBadgeProviders",)


def strings(node, path=""):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from strings(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from strings(v, f"{path}[{i}]")
    elif isinstance(node, str):
        yield path, node


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as f:
        product = json.load(f)

    errors = []
    for key, value in EXPECTED.items():
        if product.get(key) != value:
            errors.append(f"{key} = {product.get(key)!r}, expected {value!r}")
    for key, taken in TAKEN.items():
        if product.get(key) in taken:
            errors.append(f"{key} = {product.get(key)!r} collides with another editor")
    for key in FORBIDDEN_KEYS:
        if key in product:
            errors.append(f"{key} must not be set (no inherited update endpoint): {product[key]!r}")

    gallery = product.get("extensionsGallery", {})
    if not str(gallery.get("serviceUrl", "")).startswith("https://open-vsx.org/"):
        errors.append(f"extensionsGallery.serviceUrl is not Open VSX: {gallery.get('serviceUrl')!r}")

    for path, value in strings(product):
        if path.startswith(TEXT_CHECK_EXEMPT):
            continue
        lowered = value.lower()
        for text in FORBIDDEN_TEXT:
            if text in lowered:
                errors.append(f"{path} mentions {text!r}: {value!r}")

    if errors:
        print(f"check-product: {sys.argv[1]} FAILED", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)
    print(f"check-product: {sys.argv[1]} OK ({product['nameLong']}, {product['applicationName']}, {product['darwinBundleIdentifier']})")


if __name__ == "__main__":
    main()
