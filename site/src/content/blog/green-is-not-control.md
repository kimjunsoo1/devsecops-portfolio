---
title: '초록은 통제의 증거가 아니다 — GuardDuty 알림 0통 디버깅'
description: '샘플 위협을 발사했는데 메일이 오지 않았다. 지표로 측정해 가설 3개를 버리고 KMS 키 정책 공백을 찾은 과정.'
pubDate: 2026-11-10
tags: ['AWS', 'Detection', 'KMS']
---

7주차에 GuardDuty를 켜고, 심각도 4.0 이상 발견만 EventBridge → SNS → 메일로 보내도록
연결했습니다. 콘솔은 전부 초록이었습니다. 그래서 **실제로 샘플 위협을 발사해 봤습니다.**

```bash
DET=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
aws guardduty create-sample-findings --detector-id "$DET" \
  --finding-types 'Backdoor:EC2/C&CActivity.B!DNS'
```

메일은 **0통**이었습니다.

## 추측 대신 측정

알림 경로를 구간별 지표로 쪼갰습니다.

| 구간 | 지표 | 값 |
| --- | --- | --- |
| EventBridge 규칙 | Invocations | 증가 |
| EventBridge 규칙 | FailedInvocations | **100%** |
| SNS 토픽 | NumberOfMessagesPublished | **0** |

규칙은 이벤트를 받았지만 SNS에 넣지 못하고 있었습니다. 가설을 세 개 세웠고,
지표로 하나씩 확인해 셋 다 기각했습니다.

## 진짜 원인

SNS 토픽은 감사 · 알림 전용 CMK로 암호화되어 있었습니다. 그런데 **키 정책에
`events.amazonaws.com`이 없었습니다.** EventBridge는 토픽에 게시할 권한은 있었지만,
암호화에 쓸 키를 쓸 수 없었던 겁니다.

키 정책에 EventBridge 서비스 주체를 추가하자 같은 샘플로 메일이 도착했습니다.
반대로 심각도 2.0짜리 `SSHBruteForce` 샘플은 **오지 않는 것**까지 확인했습니다 —
Low 노이즈를 버리는 필터도 통제이기 때문입니다.

## 배운 것

> 스캐너의 "통과"와 콘솔의 초록은, 깨끗함과 안 봄을 구분하지 못합니다.

진단할 때 고객에게 늘 하던 말을 제 파이프라인에도 그대로 적용했습니다.
그래서 이 프로젝트의 모든 통제는 **공격으로 검증**했고, 검증 사례는 리포지토리의
`docs/security-testing.md`에 14건 남아 있습니다.
