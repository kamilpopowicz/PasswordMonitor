#!/usr/bin/env python3
import re
import sys
from pathlib import Path

SWIFT_DIRS = [Path("PasswordMonitor"), Path("PasswordMonitorCore")]
THEME_PATH = Path("PasswordMonitorCore/Theme.swift")
PMCONTROLS_PATH = Path("PasswordMonitorCore/PMControls.swift")

BANNED_STYLE_PATTERNS = [
    ("hardcoded Color.black", re.compile(r"Color\.black")),
    ("hardcoded Color.white", re.compile(r"Color\.white")),
    ("hardcoded lineWidth: 1", re.compile(r"lineWidth:\s*1\b")),
    ("hardcoded zero spacing", re.compile(r"spacing:\s*0(?:\.0)?\b")),
    ("hardcoded zero minLength", re.compile(r"minLength:\s*0(?:\.0)?\b")),
    ("hardcoded animation duration", re.compile(r"duration:\s*0\.")),
    ("hardcoded corner radius", re.compile(r"cornerRadius:\s*[0-9]")),
    ("hardcoded padding", re.compile(r"padding\([0-9]")),
    ("hardcoded frame width", re.compile(r"frame\(width:\s*[0-9]")),
    ("hardcoded opacity", re.compile(r"opacity\([0-9]")),
    (
        "hardcoded ternary opacity",
        re.compile(r"\.opacity\s*\([^)\n?]+\?\s*[01](?:\.0)?\s*:\s*[01](?:\.0)?\s*\)"),
    ),
    ("implicit padding", re.compile(r"\.padding\(\)")),
    ("implicit edge padding", re.compile(r"\.padding\(\.\w+\)")),
    ("hardcoded NSSize", re.compile(r"NSSize\(width:\s*[0-9]")),
    ("hardcoded CGSize", re.compile(r"CGSize\(width:\s*[0-9]")),
    ("hardcoded NSRect width", re.compile(r"NSRect\([^)\n]*width:\s*[0-9]")),
]

UI_LITERAL_PATTERNS = [
    ("local CGFloat UI metric", re.compile(r"\b(?:private\s+)?let\s+\w+\s*:\s*CGFloat\s*=\s*[0-9]")),
    ("literal zero spacing", re.compile(r"spacing:\s*0(?:\.0)?\b")),
    ("literal zero minLength", re.compile(r"minLength:\s*0(?:\.0)?\b")),
    ("literal spacing", re.compile(r"spacing:\s*[1-9][0-9]*")),
    ("literal corner radius", re.compile(r"cornerRadius:\s*[1-9][0-9]*")),
    ("literal padding", re.compile(r"padding\((?:\.\w+,\s*)?[1-9][0-9]*")),
    ("literal frame metric", re.compile(r"frame\((?:width|height|minWidth|maxWidth):\s*[1-9][0-9]*")),
    ("literal opacity", re.compile(r"opacity\([0-9]")),
    ("literal scale", re.compile(r"scaleEffect\([0-9]")),
    ("literal duration", re.compile(r"duration:\s*[0-9]")),
    ("literal async delay", re.compile(r"asyncAfter\(deadline:\s*.*\+\s*[0-9]")),
    ("literal NSSize", re.compile(r"NSSize\(width:\s*[0-9]")),
    ("literal CGSize", re.compile(r"CGSize\(width:\s*[0-9]")),
    ("literal NSRect width", re.compile(r"NSRect\([^)\n]*width:\s*[0-9]")),
]

LAYOUT_VISUAL_TOKEN = re.compile(
    r"PMLayout\.[A-Za-z0-9_]*(?:Opacity|Saturation|Brightness|Duration|Delay)\b"
)
LAYOUT_CONTROL_TOKEN = re.compile(
    r"PMLayout\.control[A-Z][A-Za-z0-9_]*(?:Opacity|Saturation|Brightness|FontSize|Padding|Radius)\b"
)
WRONG_SEMANTIC_USE = re.compile(r"cornerRadius:\s*PMLayout\.controlSpacing\b")

REQUIRED_WINDOW_FOOTERS = [
    Path("PasswordMonitor/AboutView.swift"),
    Path("PasswordMonitor/AIRequirementsView.swift"),
    Path("PasswordMonitor/LogsView.swift"),
    Path("PasswordMonitor/SettingsLanguageView.swift"),
    Path("PasswordMonitor/SettingsView.swift"),
]

REQUIRED_WINDOW_CONTENT_CONTAINERS = [
    Path("PasswordMonitor/AboutView.swift"),
    Path("PasswordMonitor/AIRequirementsView.swift"),
    Path("PasswordMonitor/LogsView.swift"),
    Path("PasswordMonitor/SettingsView.swift"),
]


def swift_files() -> list[Path]:
    files: list[Path] = []
    for base in SWIFT_DIRS:
        files.extend(sorted(base.rglob("*.swift")))
    return files


def line_for_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def add_matches(
    failures: list[str],
    path: Path,
    text: str,
    checks: list[tuple[str, re.Pattern[str]]],
) -> None:
    for label, pattern in checks:
        for match in pattern.finditer(text):
            line = line_for_offset(text, match.start())
            snippet = text[match.start() : match.end()].strip()
            failures.append(f"{path}:{line}: {label}: {snippet}")


def enum_body(text: str, enum_name: str) -> str:
    start = text.find(f"public enum {enum_name}")
    if start == -1:
        return ""
    brace = text.find("{", start)
    if brace == -1:
        return ""

    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1 : index]
    return ""


def main() -> int:
    failures: list[str] = []
    files = swift_files()

    for path in files:
        text = path.read_text()
        add_matches(failures, path, text, BANNED_STYLE_PATTERNS)

        if path != THEME_PATH:
            add_matches(failures, path, text, UI_LITERAL_PATTERNS)

        for pattern, label in [
            (LAYOUT_VISUAL_TOKEN, "visual/control value stored in PMLayout"),
            (LAYOUT_CONTROL_TOKEN, "control metric should use PMControlMetrics"),
            (WRONG_SEMANTIC_USE, "spacing token used as corner radius"),
        ]:
            for match in pattern.finditer(text):
                line = line_for_offset(text, match.start())
                failures.append(f"{path}:{line}: {label}: {match.group(0)}")

    if THEME_PATH.exists():
        theme_text = THEME_PATH.read_text()
        pm_theme_body = enum_body(theme_text, "PMTheme")
        pm_layout_body = enum_body(theme_text, "PMLayout")
        pm_control_metrics_body = enum_body(theme_text, "PMControlMetrics")

        if "PMLayout." in pm_theme_body:
            failures.append(f"{THEME_PATH}: PMTheme must not depend on PMLayout")

        if "PMLayout." in pm_control_metrics_body:
            failures.append(f"{THEME_PATH}: PMControlMetrics must not depend on PMLayout")

        layout_bad = re.search(r"public static let \w*(?:Opacity|Saturation|Brightness|Duration|Delay)\b", pm_layout_body)
        if layout_bad:
            line = line_for_offset(theme_text, theme_text.find(layout_bad.group(0)))
            failures.append(f"{THEME_PATH}:{line}: PMLayout contains non-layout token: {layout_bad.group(0)}")

    if PMCONTROLS_PATH.exists():
        controls_text = PMCONTROLS_PATH.read_text()
        if "PMLayout.panelShadowOpacity" in controls_text:
            failures.append(f"{PMCONTROLS_PATH}: PMControls must not use panelShadowOpacity for control state")
        if "PMControlMetrics" not in controls_text:
            failures.append(f"{PMCONTROLS_PATH}: PMControls must use PMControlMetrics")

    for path in REQUIRED_WINDOW_FOOTERS:
        if path.exists():
            text = path.read_text()
            if "PMWindowFooterHost()" not in text:
                failures.append(f"{path}: window view must include PMWindowFooterHost()")
            if "PMWindowFooter()" in text:
                failures.append(f"{path}: window view must use PMWindowFooterHost(), not PMWindowFooter() directly")

    for path in REQUIRED_WINDOW_CONTENT_CONTAINERS:
        if path.exists() and "PMWindowContentContainer" not in path.read_text():
            failures.append(f"{path}: window content must use PMWindowContentContainer")

    if failures:
        print("Theme Guard check failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("Theme Guard check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
