---
title: '억제에도 기한이 있다 — 사람 대신 CI가 약속을 지키게 하기'
description: '수용한 발견사항에 근거와 재검토 기한을 붙이고, 기한이 지나면 게이트를 실패시키는 장치. 이 장치가 WAF 도입을 앞당겼다.'
pubDate: 2026-11-04
tags: ['IaC', 'Checkov', 'Governance']
---

진단 결과 보고 자리에서 가장 자주 듣는 말 중 하나가 "그건 위험 수용으로 할게요"입니다.
문제는 그 수용이 **언제 다시 검토되는지 아무도 모른다**는 겁니다.

## 규칙

Checkov 발견사항을 수용할 때는 코드 바로 옆에 근거를 적고, 둘 중 하나를 붙입니다.

- `permanent` — 구조적으로 해당 없음
- `revisit=YYYY-MM-DD` — 이 날짜에 다시 본다

`scripts/check-suppressions.py`가 CI에서 근거 30자 미만, 기한 누락, **기한 만료**를
모두 실패로 만듭니다.

```text
$ python3 scripts/check-suppressions.py --list
terraform/site/cloudfront.tf:64  CKV_AWS_86   revisit=2027-02-01
terraform/site/s3.tf:14          CKV_AWS_145  permanent
...
총 24건
```

## 실제로 일어난 일

2주 동안 손을 대지 않는 사이, CloudFront WAF 미적용 억제의 기한이 지났습니다.
게이트가 막혔고, 더는 WAF 결정을 미룰 수 없었습니다. 그래서 WAF를 붙였고,
붙인 뒤에는 LFI · XSS · Log4Shell 요청을 직접 보내 차단을 확인했습니다.

**사람의 기억이 아니라 기계가 약속을 지킨 사례입니다.**

## 같은 규율을 계정 전역에도

Prowler 계정 스캔에서 나온 63건도 N/A · ACCEPT · REVISIT로 전수 분류해
`prowler-mutelist.yaml`에 근거와 기한을 달았습니다. 의존성 취약점은 수정 버전이 없을 때만
`.trivyignore.yaml`에 `expired_at`으로 억제합니다.

단 하나, 가장 위험한 SSO `AdministratorAccess`는 **숨기지 않고 백로그에 남겼습니다.**
억제 장치는 위험을 감추는 도구가 아니라, 위험을 기한이 있는 약속으로 바꾸는 도구여야 하니까요.
