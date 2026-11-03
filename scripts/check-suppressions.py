#!/usr/bin/env python3
"""억제 주석의 품질과 기한을 검사합니다.

Checkov 인라인 억제(#checkov:skip=ID:근거)에는 Trivy 의 expired_at 같은
기한 장치가 없습니다. 한 번 달면 지울 때까지 영원히 조용합니다.
이 스크립트가 그 역할을 대신합니다.

규칙
  1. 근거가 30자 미만이면 실패 - ID 만 나열하는 억제는 스캐너를 끄는 것과 같다
  2. 근거에 revisit=YYYY-MM-DD 또는 permanent 가 없으면 실패
  3. revisit 날짜가 오늘 이전이면 실패 - 다시 판단할 시점이 지났다
  4. revisit 이 30일 안이면 경고 (실패는 아님)

사용
  python3 scripts/check-suppressions.py          # 검사
  python3 scripts/check-suppressions.py --list    # 전체 목록만 출력
"""
from __future__ import annotations

import re
import sys
from datetime import date, timedelta
from pathlib import Path

SKIP_RE = re.compile(r"#\s*checkov:skip=([A-Z0-9_]+):(.*)$")
REVISIT_RE = re.compile(r"revisit=(\d{4})-(\d{2})-(\d{2})")

MIN_REASON = 30
WARN_WINDOW = 30
SCAN_GLOBS = ("terraform/**/*.tf",)


def collect(root: Path):
    found = []
    for pattern in SCAN_GLOBS:
        for path in sorted(root.glob(pattern)):
            for lineno, line in enumerate(path.read_text().splitlines(), 1):
                m = SKIP_RE.search(line)
                if m:
                    found.append(
                        {
                            "file": path.relative_to(root).as_posix(),
                            "line": lineno,
                            "rule": m.group(1),
                            "reason": m.group(2).strip(),
                        }
                    )
    return found


def main() -> int:
    root = Path.cwd()
    if not (root / "terraform").is_dir():
        print("오류: 레포 루트에서 실행하세요 (terraform/ 가 보이지 않습니다)")
        return 2

    items = collect(root)
    today = date.today()
    errors, warnings = [], []

    for it in items:
        where = f"{it['file']}:{it['line']}  {it['rule']}"
        reason = it["reason"]

        if len(reason) < MIN_REASON:
            errors.append(f"{where}\n    근거가 {len(reason)}자 (최소 {MIN_REASON}자). 왜 수용하는지 쓰세요.")
            continue

        m = REVISIT_RE.search(reason)
        permanent = "permanent" in reason

        if not m and not permanent:
            errors.append(f"{where}\n    revisit=YYYY-MM-DD 또는 permanent 표기가 없습니다.")
            continue

        if permanent and m:
            errors.append(f"{where}\n    permanent 와 revisit 이 함께 있습니다. 하나만 쓰세요.")
            continue

        if m:
            due = date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            if due <= today:
                errors.append(
                    f"{where}\n    revisit={due} 이 지났습니다 (오늘 {today}). "
                    f"고치거나, 근거를 갱신하고 날짜를 미루거나, permanent 로 종결하세요."
                )
            elif due - today <= timedelta(days=WARN_WINDOW):
                warnings.append(f"{where}  revisit={due} ({(due - today).days}일 남음)")

    if "--list" in sys.argv:
        for it in items:
            tag = "permanent" if "permanent" in it["reason"] else (
                REVISIT_RE.search(it["reason"]).group(0)
                if REVISIT_RE.search(it["reason"]) else "표기없음"
            )
            print(f"{it['file']}:{it['line']}  {it['rule']:16} {tag}")
        print(f"\n총 {len(items)}건")
        return 0

    print(f"억제 주석 {len(items)}건 검사")

    if warnings:
        print(f"\n곧 만료 {len(warnings)}건")
        for w in warnings:
            print(f"  {w}")

    if errors:
        print(f"\n실패 {len(errors)}건")
        for e in errors:
            print(f"  {e}")
        return 1

    print("OK — 모든 억제에 근거와 기한 표기가 있고, 만료된 항목이 없습니다")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
