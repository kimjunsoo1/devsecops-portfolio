#!/usr/bin/env python3
"""
GitHub Actions 를 커밋 SHA 로 고정합니다.

    uses: actions/checkout@v4
    -> uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v4

태그는 옮길 수 있습니다. 공격자가 액션 리포지토리를 장악하면
v4 태그를 자기 커밋으로 옮겨서 우리 CI 안에서 코드를 실행할 수 있습니다.
2025년 tj-actions/changed-files 사건이 정확히 이 경로였습니다.

커밋 SHA 는 옮길 수 없습니다. 뒤에 남기는 `# v4` 주석은 사람이 읽기 위한
것이면서, Dependabot 이 어떤 버전에서 올려야 하는지 판단하는 근거이기도 합니다.

사용법:
    gh auth status          # 먼저 로그인되어 있어야 합니다
    python3 scripts/pin-actions.py            # 확인만
    python3 scripts/pin-actions.py --write    # 실제 수정
"""

import re
import subprocess
import sys
from pathlib import Path

USES = re.compile(
    r"^(?P<indent>\s*-?\s*uses:\s*)"
    r"(?P<action>[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+)"
    r"@(?P<ref>[A-Za-z0-9._-]+)"
    r"(?P<rest>\s*(?:#.*)?)$"
)

SHA40 = re.compile(r"^[0-9a-f]{40}$")


def resolve(repo: str, ref: str):
    """태그/브랜치를 커밋 SHA 로 해석합니다."""
    proc = subprocess.run(
        ["gh", "api", f"repos/{repo}/commits/{ref}", "--jq", ".sha"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None, proc.stderr.strip().splitlines()[-1] if proc.stderr else "실패"
    return proc.stdout.strip(), None


def main() -> int:
    write = "--write" in sys.argv
    workflows = sorted(Path(".github/workflows").glob("*.y*ml"))

    if not workflows:
        print("워크플로 파일이 없습니다.")
        return 1

    cache: dict[tuple[str, str], str] = {}
    changed_files = 0
    pinned = 0
    skipped = 0

    for path in workflows:
        lines = path.read_text(encoding="utf-8").split("\n")
        touched = False

        for i, line in enumerate(lines):
            m = USES.match(line)
            if not m:
                continue

            action = m.group("action")
            ref = m.group("ref")

            if SHA40.match(ref):
                continue  # 이미 고정됨

            # github/codeql-action/upload-sarif -> github/codeql-action
            repo = "/".join(action.split("/")[:2])

            key = (repo, ref)
            if key not in cache:
                sha, err = resolve(repo, ref)
                if sha is None:
                    print(f"  건너뜀  {action}@{ref}  ({err})")
                    skipped += 1
                    continue
                cache[key] = sha

            sha = cache[key]
            lines[i] = f"{m.group('indent')}{action}@{sha} # {ref}"
            print(f"  고정    {action}@{ref}  ->  {sha[:12]}…")
            pinned += 1
            touched = True

        if touched:
            changed_files += 1
            if write:
                path.write_text("\n".join(lines), encoding="utf-8")

    print()
    print(f"고정 {pinned}건 · 건너뜀 {skipped}건 · 파일 {changed_files}개")
    if not write and pinned:
        print("실제로 반영하려면: python3 scripts/pin-actions.py --write")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
