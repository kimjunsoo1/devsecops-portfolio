#!/usr/bin/env python3
"""
GitHub Actions 를 커밋 SHA 로 고정하고, 워크플로 사이의 버전 일관성을 지킵니다.

    uses: actions/checkout@v4
    -> uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

태그는 옮길 수 있습니다. 액션 리포지토리를 장악한 공격자가 v4 태그를 자기
커밋으로 옮기면, 그 액션을 쓰는 모든 워크플로가 다음 실행부터 그 코드를
돌립니다. 2025년 tj-actions/changed-files 사건이 이 경로였습니다.
커밋 SHA 는 옮길 수 없습니다.

뒤에 남기는 `# v7.0.1` 주석은 사람이 읽기 위한 것이면서, Dependabot 이
어떤 버전에서 올려야 하는지 판단하는 근거이기도 합니다.

--------------------------------------------------------------------------
왜 --check 와 --align 이 생겼는가

처음 이 스크립트는 "태그 -> SHA" 변환만 했습니다. 그런데 새 워크플로를
추가할 때마다 같은 함정에 빠졌습니다. 새 파일에 `@v4` 라고 적으면
스크립트가 v4 의 SHA 를 박는데, 기존 워크플로는 Dependabot 이 이미
v7 로 올려둔 상태였습니다. 결과적으로 워크플로마다 checkout 버전이
갈렸고, 세 번 반복된 뒤에야 도구의 한계로 인식했습니다.

도구가 "고정했는가" 만 보고 "일관되게 고정했는가" 는 보지 않았던 것입니다.

사용법:
    python3 scripts/pin-actions.py              # 무엇이 바뀔지 확인만
    python3 scripts/pin-actions.py --write      # 태그를 SHA 로 고정
    python3 scripts/pin-actions.py --align      # 액션별로 SHA 를 하나로 통일
    python3 scripts/pin-actions.py --check      # CI 용. 문제가 있으면 종료 코드 1
"""

import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

USES = re.compile(
    r"^(?P<indent>\s*-?\s*uses:\s*)"
    r"(?P<action>[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+)"
    r"@(?P<ref>[A-Za-z0-9._-]+)"
    r"(?P<rest>\s*(?:#\s*(?P<comment>\S+))?.*)$"
)

SHA40 = re.compile(r"^[0-9a-f]{40}$")
WORKFLOWS = sorted(Path(".github/workflows").glob("*.y*ml"))


def resolve(repo: str, ref: str):
    """태그/브랜치를 커밋 SHA 로 해석합니다."""
    proc = subprocess.run(
        ["gh", "api", f"repos/{repo}/commits/{ref}", "--jq", ".sha"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        tail = proc.stderr.strip().splitlines()
        return None, tail[-1] if tail else "실패"
    return proc.stdout.strip(), None


def scan():
    """모든 워크플로에서 액션 참조를 수집합니다."""
    found = []  # (path, lineno, action, ref, comment)
    for path in WORKFLOWS:
        for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")):
            m = USES.match(line)
            if m:
                found.append((path, i, m.group("action"), m.group("ref"), m.group("comment")))
    return found


def pin(write: bool) -> int:
    cache, pinned, skipped, files = {}, 0, 0, set()
    for path in WORKFLOWS:
        lines = path.read_text(encoding="utf-8").split("\n")
        touched = False
        for i, line in enumerate(lines):
            m = USES.match(line)
            if not m or SHA40.match(m.group("ref")):
                continue
            action, ref = m.group("action"), m.group("ref")
            repo = "/".join(action.split("/")[:2])
            if (repo, ref) not in cache:
                sha, err = resolve(repo, ref)
                if sha is None:
                    print(f"  건너뜀  {action}@{ref}  ({err})")
                    skipped += 1
                    continue
                cache[(repo, ref)] = sha
            sha = cache[(repo, ref)]
            lines[i] = f"{m.group('indent')}{action}@{sha} # {ref}"
            print(f"  고정    {action}@{ref}  ->  {sha[:12]}…  ({path.name})")
            pinned += 1
            touched = True
        if touched:
            files.add(path)
            if write:
                path.write_text("\n".join(lines), encoding="utf-8")
    print(f"\n고정 {pinned}건 · 건너뜀 {skipped}건 · 파일 {len(files)}개")
    if not write and pinned:
        print("실제로 반영하려면: python3 scripts/pin-actions.py --write")
    return skipped


def inconsistencies():
    """같은 액션이 서로 다른 SHA 로 쓰이는 곳을 찾습니다."""
    by_action = defaultdict(list)
    for path, lineno, action, ref, comment in scan():
        if SHA40.match(ref):
            by_action[action].append((path, lineno, ref, comment))
    return {a: uses for a, uses in by_action.items() if len({u[2] for u in uses}) > 1}


def align(write: bool) -> int:
    bad = inconsistencies()
    if not bad:
        print("  모든 액션이 하나의 SHA 로 통일되어 있습니다.")
        return 0

    for action, uses in bad.items():
        # 가장 많이 쓰인 SHA 를 정답으로 봅니다. 새로 추가한 파일 한 곳이
        # 옛 태그로 고정되는 것이 전형적인 어긋남이기 때문입니다.
        winner, _ = Counter(u[2] for u in uses).most_common(1)[0]
        comment = next((u[3] for u in uses if u[2] == winner and u[3]), None)
        print(f"\n  {action}")
        print(f"    기준 SHA  {winner[:12]}…  {('# ' + comment) if comment else ''}")
        for path, lineno, ref, _c in uses:
            if ref == winner:
                continue
            print(f"    맞춤      {path.name}:{lineno + 1}  {ref[:12]}…  ->  {winner[:12]}…")
            if write:
                lines = path.read_text(encoding="utf-8").split("\n")
                m = USES.match(lines[lineno])
                tail = f" # {comment}" if comment else ""
                lines[lineno] = f"{m.group('indent')}{action}@{winner}{tail}"
                path.write_text("\n".join(lines), encoding="utf-8")
    if not write:
        print("\n실제로 반영하려면: python3 scripts/pin-actions.py --align --write")
    return len(bad)


def check() -> int:
    """CI 용 검사. 미고정과 불일치 둘 다 실패 조건입니다."""
    problems = 0

    unpinned = [(p, i, a, r) for p, i, a, r, _ in scan() if not SHA40.match(r)]
    if unpinned:
        print("고정되지 않은 액션:")
        for path, lineno, action, ref in unpinned:
            print(f"  {path}:{lineno + 1}  {action}@{ref}")
        problems += len(unpinned)
    else:
        print("고정 검사  OK — 모든 액션이 커밋 SHA 로 고정됨")

    bad = inconsistencies()
    if bad:
        print("\n같은 액션이 서로 다른 SHA 로 쓰임:")
        for action, uses in bad.items():
            print(f"  {action}")
            for path, lineno, ref, comment in sorted(uses, key=lambda u: (u[0].name, u[1])):
                tag = f" # {comment}" if comment else ""
                print(f"    {path.name}:{lineno + 1}  {ref[:12]}…{tag}")
        problems += len(bad)
    else:
        print("일관성 검사  OK — 액션별 SHA 가 하나로 통일됨")

    if problems:
        print("\n수정: python3 scripts/pin-actions.py --write  후  --align --write")
        return 1
    return 0


def main() -> int:
    if not WORKFLOWS:
        print("워크플로 파일이 없습니다.")
        return 1

    args = set(sys.argv[1:])
    write = "--write" in args

    if "--check" in args:
        return check()

    if "--align" in args:
        return 1 if align(write) and not write else 0

    skipped = pin(write)
    bad = inconsistencies()
    if bad:
        print(f"\n경고: 같은 액션이 서로 다른 SHA 로 쓰이고 있습니다 ({len(bad)}종).")
        print("      python3 scripts/pin-actions.py --align  로 확인하세요.")
    return 1 if skipped else 0


if __name__ == "__main__":
    raise SystemExit(main())
