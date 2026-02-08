#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

CATALOG_PATH = Path("PasswordMonitor/Localizable.xcstrings")
SWIFT_DIRS = [Path("PasswordMonitor"), Path("PasswordMonitorCore")]

KEY_PATTERNS = [
    re.compile(r'logLocalized\(\s*"([^"]+)"'),
    re.compile(r'localizedString\(\s*"([^"]+)"'),
    re.compile(r'String\(localized:\s*"([^"]+)"'),
    re.compile(r'LocalizedStringKey\(\s*"([^"]+)"'),
    re.compile(r'\.alert\(\s*"([^"]+)"'),
    re.compile(r'\.navigationTitle\(\s*"([^"]+)"'),
    re.compile(r'\b(Text|Button|Toggle|Picker|MenuBarExtra|Window|TextField|DatePicker)\(\s*"([^"]+)"'),
    re.compile(r'Text\(\s*"([^"]+)"\s*\)'),
]


def collect_used_keys() -> set[str]:
    keys: set[str] = set()
    for base in SWIFT_DIRS:
        for path in base.rglob("*.swift"):
            text = path.read_text()
            for pattern in KEY_PATTERNS:
                for match in pattern.finditer(text):
                    if match.lastindex == 1:
                        keys.add(match.group(1))
                    else:
                        keys.add(match.group(2))
    return keys


def load_catalog_keys() -> set[str]:
    data = json.loads(CATALOG_PATH.read_text())
    return set(data.get("strings", {}).keys())


def main() -> int:
    if not CATALOG_PATH.exists():
        print(f"Missing catalog: {CATALOG_PATH}")
        return 2

    used = collect_used_keys()
    catalog = load_catalog_keys()

    missing = sorted(used - catalog)
    unused = sorted(catalog - used)

    if missing:
        print("Missing localization keys (used in code, not in catalog):")
        for k in missing:
            print(f"  - {k}")

    if unused:
        print("Unused localization keys (in catalog, not used in code):")
        for k in unused:
            print(f"  - {k}")

    if missing:
        return 1

    print("Localization check passed.")
    if unused:
        print(f"Note: {len(unused)} unused keys in catalog.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
