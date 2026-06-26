#!/usr/bin/env python3
import argparse
import re
import subprocess
from collections import OrderedDict
from pathlib import Path


def run_git(args: list[str]) -> str:
    return subprocess.check_output(["git", *args], text=True).strip()


def latest_tag(tag_prefix: str) -> str | None:
    tags = run_git(["tag", "--list", f"{tag_prefix}*", "--sort=-v:refname"]).splitlines()
    return tags[0] if tags else None


def commit_subjects(previous_tag: str | None) -> list[str]:
    # 使用上一个统一版本标签作为边界，让 Android 与 macOS 共用同一份发布说明。
    range_args = [f"{previous_tag}..HEAD"] if previous_tag else []
    output = run_git(["log", "--no-merges", "--pretty=format:%s", *range_args])
    return [line.strip() for line in output.splitlines() if line.strip()]


def append_unique(target: OrderedDict[str, None], value: str) -> None:
    clean_value = value.strip()
    if clean_value:
        target.setdefault(clean_value, None)


def classify_subjects(subjects: list[str]) -> tuple[list[str], list[str], list[str]]:
    features: OrderedDict[str, None] = OrderedDict()
    fixes: OrderedDict[str, None] = OrderedDict()
    others: OrderedDict[str, None] = OrderedDict()

    for subject in subjects:
        match = re.match(r"^(feat|fix)(?:\([^)]+\))?!?:\s*(.+)$", subject, re.IGNORECASE)
        if not match:
            append_unique(others, subject)
            continue

        kind = match.group(1).lower()
        content = match.group(2).strip()
        if kind == "feat":
            append_unique(features, content)
        elif kind == "fix":
            append_unique(fixes, content)

    return list(features.keys()), list(fixes.keys()), list(others.keys())


def append_section(lines: list[str], title: str, entries: list[str]) -> None:
    if not entries:
        return
    lines.append(f"### {title}")
    for entry in entries:
        lines.append(f"- {entry}")
    lines.append("")


def build_markdown(version: str, previous_tag: str | None, subjects: list[str], platform: str | None = None) -> str:
    features, fixes, others = classify_subjects(subjects)
    release_title = f"CastPigeon {platform} v{version}" if platform else f"CastPigeon v{version}"
    lines = [
        f"## {release_title}",
        "",
    ]

    append_section(lines, "功能更新", features)
    append_section(lines, "问题修复", fixes)
    append_section(lines, "其他更新", others)

    if not features and not fixes and not others:
        lines.extend([
            "### 其他更新",
            f"- 发布 {release_title}",
            "",
        ])

    if previous_tag:
        lines.extend([
            "### 发布范围",
            f"- {previous_tag}..HEAD",
            "",
        ])

    return "\n".join(lines).strip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate CastPigeon GitHub Release changelog.")
    parser.add_argument("--platform")
    parser.add_argument("--version", required=True)
    parser.add_argument("--tag-prefix", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    previous_tag = latest_tag(args.tag_prefix)
    subjects = commit_subjects(previous_tag)
    markdown = build_markdown(args.version, previous_tag, subjects, args.platform)
    Path(args.output).write_text(markdown, encoding="utf-8")


if __name__ == "__main__":
    main()
