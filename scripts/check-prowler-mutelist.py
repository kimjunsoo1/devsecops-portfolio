#!/usr/bin/env python3
"""Prowler mutelist 의 모든 억제 항목에 [분류]+근거+기한 태그가 있는지 검증한다.
Checkov 의 check-suppressions.py 와 동일 철학 — "억제엔 반드시 근거와 기한".

규칙: Checks: 아래 각 체크 키("check_id":) 바로 윗줄은 다음 형식의 주석이어야 한다.
    # [N/A|ACCEPT|REVISIT] <근거 8자 이상> | <permanent | revisit=YYYY-MM-DD>
revisit 기한이 지났으면 실패(= 재검토 강제).

사용: python3 scripts/check-prowler-mutelist.py [mutelist.yaml]
"""
import datetime as dt
import re
import sys
from pathlib import Path

DEFAULT = Path("prowler-mutelist.yaml")
CHECK_KEY = re.compile(r'^\s*"([a-z0-9_]+)"\s*:')
TAG = re.compile(
    r'^\s*#\s*\[(N/A|ACCEPT|REVISIT)\]\s*(.+?)\s*\|\s*'
    r'(permanent|revisit=(\d{4}-\d{2}-\d{2}))\s*$'
)


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    if not path.exists():
        print(f"오류: {path} 없음", file=sys.stderr)
        return 2

    lines = path.read_text(encoding="utf-8").splitlines()
    today = dt.date.today()
    errors, count = [], 0

    for i, ln in enumerate(lines):
        m = CHECK_KEY.match(ln)
        if not m:
            continue
        cid = m.group(1)
        count += 1

        # 바로 위 비어있지 않은 줄
        j = i - 1
        while j >= 0 and lines[j].strip() == "":
            j -= 1
        prev = lines[j] if j >= 0 else ""

        tm = TAG.match(prev)
        if not tm:
            errors.append(f"{cid}: 윗줄에 '# [분류] 근거 | 기한' 태그가 없음")
            continue
        rationale, tag, date = tm.group(2), tm.group(3), tm.group(4)
        if len(rationale.replace(" ", "")) < 8:
            errors.append(f"{cid}: 근거가 너무 짧음({rationale!r})")
        if date:
            try:
                d = dt.date.fromisoformat(date)
                if d < today:
                    errors.append(f"{cid}: revisit 기한 지남({date}) — 재검토 필요")
            except ValueError:
                errors.append(f"{cid}: 기한 형식 오류({date})")

    print(f"mutelist 억제 {count}건 검사")
    if errors:
        print(f"실패 — {len(errors)}건:")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("OK — 모든 억제에 분류·근거·기한 표기가 있고, 만료된 항목이 없습니다")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
