#!/usr/bin/env python3
"""중앙 GitHub 자산의 구조와 불변 참조를 검증한다."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
FULL_SHA = re.compile(r"[0-9a-f]{40}")
USES = re.compile(r"^\s*uses:\s*([^\s#]+)", re.MULTILINE)
BOOTSTRAP_REF = "__CENTRAL_WORKFLOW_SHA__"

REQUIRED_FILES = (
    "README.md",
    "AGENTS.md",
    "LICENSE",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "GOVERNANCE.md",
    "SECURITY.md",
    "SUPPORT.md",
    "NOTICE.md",
    "profile/README.md",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/dependabot.yml",
)

REQUIRED_GATES = (
    "CI / gate",
    "PR Policy / gate",
    "Dependency Review / gate",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--allow-bootstrap-ref",
        action="store_true",
        help="첫 commit을 만들 때만 template의 임시 중앙 참조를 허용합니다.",
    )
    return parser.parse_args()


def load_yaml(path: Path, errors: list[str]) -> object | None:
    try:
        return yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    except (OSError, yaml.YAMLError) as exc:
        errors.append(f"{path.relative_to(ROOT)}: YAML 파싱 실패: {exc}")
        return None


def validate_required_files(errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        if not (ROOT / relative).is_file():
            errors.append(f"필수 파일 누락: {relative}")

    issue_forms = ROOT / ".github" / "ISSUE_TEMPLATE"
    for name in ("bug-report.yml", "feature-request.yml", "data-report.yml", "config.yml"):
        if not (issue_forms / name).is_file():
            errors.append(f"Issue Template 누락: .github/ISSUE_TEMPLATE/{name}")


def validate_yaml_and_json(errors: list[str]) -> None:
    yaml_files = sorted(ROOT.glob(".github/**/*.yml")) + sorted(
        ROOT.glob("workflow-templates/*.yml")
    )
    for path in yaml_files:
        load_yaml(path, errors)

    for path in sorted(ROOT.glob("workflow-templates/*.properties.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"{path.relative_to(ROOT)}: JSON 파싱 실패: {exc}")
            continue
        for key in ("name", "description", "iconName", "categories"):
            if key not in data:
                errors.append(f"{path.relative_to(ROOT)}: {key} 누락")


def validate_workflow_shape(errors: list[str]) -> None:
    workflows = ROOT / ".github" / "workflows"
    for path in sorted(workflows.glob("reusable-*.yml")):
        data = load_yaml(path, errors)
        if not isinstance(data, dict):
            continue
        trigger = data.get("on")
        if not isinstance(trigger, dict) or "workflow_call" not in trigger:
            errors.append(f"{path.relative_to(ROOT)}: on.workflow_call 누락")
        if "permissions" not in data:
            errors.append(f"{path.relative_to(ROOT)}: top-level permissions 누락")

    gate_files = [workflows / "ci.yml", *sorted((ROOT / "workflow-templates").glob("*.yml"))]
    for path in gate_files:
        text = path.read_text(encoding="utf-8")
        for gate in REQUIRED_GATES:
            if f"name: {gate}" not in text:
                errors.append(f"{path.relative_to(ROOT)}: 안정적인 check 이름 '{gate}' 누락")
        if re.search(r"^\s+paths(?:-ignore)?:", text, re.MULTILINE):
            errors.append(f"{path.relative_to(ROOT)}: required workflow에 path filter 사용 금지")
        if "pull_request_target" in text:
            errors.append(f"{path.relative_to(ROOT)}: pull_request_target 사용 금지")


def validate_template_pairs(errors: list[str]) -> None:
    template_dir = ROOT / "workflow-templates"
    yamls = {path.stem for path in template_dir.glob("*.yml")}
    properties = {
        path.name.removesuffix(".properties.json")
        for path in template_dir.glob("*.properties.json")
    }
    if yamls != properties:
        errors.append(
            "workflow template/property 쌍 불일치: "
            f"YAML-only={sorted(yamls - properties)}, JSON-only={sorted(properties - yamls)}"
        )


def validate_immutable_uses(errors: list[str], allow_bootstrap_ref: bool) -> None:
    candidates = sorted(ROOT.glob(".github/workflows/*.yml")) + sorted(
        ROOT.glob("workflow-templates/*.yml")
    )
    for path in candidates:
        text = path.read_text(encoding="utf-8")
        for target in USES.findall(text):
            if target.startswith("./") or target.startswith("docker://"):
                continue
            if "@" not in target:
                errors.append(f"{path.relative_to(ROOT)}: ref 없는 uses: {target}")
                continue
            reference = target.rsplit("@", 1)[1]
            if reference == BOOTSTRAP_REF and allow_bootstrap_ref:
                continue
            if not FULL_SHA.fullmatch(reference):
                errors.append(
                    f"{path.relative_to(ROOT)}: 전체 commit SHA가 아닌 uses ref: {target}"
                )


def main() -> int:
    args = parse_args()
    errors: list[str] = []
    validate_required_files(errors)
    validate_yaml_and_json(errors)
    validate_workflow_shape(errors)
    validate_template_pairs(errors)
    validate_immutable_uses(errors, args.allow_bootstrap_ref)

    if errors:
        print("중앙 GitHub 자산 검증 실패:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print("중앙 GitHub 자산 검증 통과")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
