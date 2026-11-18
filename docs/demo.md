# 데모 시나리오 — devsecops-portfolio

/ 목적: 구축한 통제가 **실제로 동작함**을 공격→탐지→알림→대응으로 시연한다.
각 데모는 위협모델(threat-model.md)과 런북(runbook.md)의 특정 항목에 연결된다.

> 공통 메시지: "스캐너 초록은 통제의 증거가 아니다. 그래서 전부 공격으로 검증했다."

## 5분 데모 (면접용 핵심 경로)

시간이 없으면 **Demo A 하나**만 보여준다 — 탐지 파이프라인이 실제 메일까지
도달함을 증명하고, 이 프로젝트에서 가장 값진 디버깅 서사(KMS 키 정책 공백)를 곁들인다.

---

## Demo A — 위협 탐지 → 알림 → 대응 (GuardDuty)

- **연결**: 위협모델 D/E, 런북 §1-6
- **한 줄**: 공격 모사 → GuardDuty 탐지 → EventBridge(sev≥4) → SNS → 메일 → 런북 대응

### 실행
```bash
DET=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
set +H
# High 심각도 위협 모사 (실제 리소스 영향 없음, 합성 finding)
aws guardduty create-sample-findings --detector-id "$DET" \
  --finding-types 'Backdoor:EC2/C&CActivity.B!DNS'
```

### 기대 결과 / 보여줄 화면
1. **메일 도착**: 제목 `[GuardDuty] 심각도 8 | Backdoor:EC2/C&CActivity.B!DNS`
2. **GuardDuty 콘솔**: finding 상세(주체·IP·리소스)
3. **경로 증명**(원하면): EventBridge 규칙 Invocations 지표 > 0
```bash
aws cloudwatch get-metric-statistics --namespace AWS/SNS \
  --metric-name NumberOfMessagesPublished \
  --dimensions Name=TopicName,Value=devsecops-portfolio-billing-alerts \
  --start-time "$(date -u -d '10 min ago' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 60 --statistics Sum --query 'Datapoints[].Sum'
```

### 대응 시연 (런북 §1-6)
- finding 유형 확인 → `Backdoor` → 관련 리소스 격리 절차 설명.
- **저심각도 필터링 시연**: `SSHBruteForce`(sev 2.0) 샘플은 메일이 **안 온다** →
  `severity>=4.0` 필터가 Low 노이즈를 버림(의도된 negative 통제).

### 정리
```bash
# 데모용 finding 아카이브
while :; do
  IDS=$(aws guardduty list-findings --detector-id "$DET" \
    --finding-criteria '{"Criterion":{"service.archived":{"Eq":["false"]}}}' \
    --max-results 50 --query 'FindingIds' --output text)
  [ -z "$IDS" ] && break
  aws guardduty archive-findings --detector-id "$DET" --finding-ids $IDS
done
```

### 서사 포인트
"처음엔 메일이 0통이었다. 지표로 측정하니 EventBridge 호출은 100% 실패,
SNS 발행은 0 — 가설 3개를 기각하고 **SNS 토픽 CMK 키 정책에 EventBridge
누락**이라는 진짜 원인에 도달했다. 초록이 통제를 뜻하지 않는다는 산 증거."

---

## Demo B — 감사 은폐 탐지 (CloudTrail 변경)

- **연결**: 위협모델 R/T, 런북 §1-5
- **한 줄**: 공격자가 로깅을 끄려 함 → 메트릭 필터가 포착 → 알람 → 메일

### 실행 (두 옵션)
**옵션 1 — 안전(권장, 로깅 유지)**: 설정 변경 이벤트만 유발
```bash
# PutEventSelectors 는 cloudtrail-config-change 필터에 걸린다 (로깅은 계속)
aws cloudtrail put-event-selectors --trail-name devsecops-portfolio-trail \
  --event-selectors '[{"ReadWriteType":"All","IncludeManagementEvents":true}]'
```
**옵션 2 — 실제 anti-forensics 모사**: 로깅 중단 후 즉시 재개
```bash
aws cloudtrail stop-logging  --name devsecops-portfolio-trail
aws cloudtrail start-logging --name devsecops-portfolio-trail   # 즉시 재개
```

### 기대 결과 / 보여줄 화면
- 수 분 내(CloudTrail→CWL 전달 지연) 알람 `ALARM` 전환 + 메일.
- 알람 확인:
```bash
aws cloudwatch describe-alarms \
  --alarm-names devsecops-portfolio-cloudtrail-config-change \
  --query 'MetricAlarms[0].{state:StateValue,updated:StateUpdatedTimestamp}'
```

### 대응 시연 (런북 §1-5)
- 옵션 2였다면 로깅 **공백 구간**을 식별하고 재개 확인, 주체 추적을 설명.

### 서사 포인트
"Prowler 로 측정했더니 CIS 3.5 커버리지에 공백이 있었다 —
CreateTrail/StartLogging 이 필터에 없어 실제 탐지 구멍이었고, 메꿨다."

---

## Demo C — 파이프라인 방어 (shift-left 게이트)

- **연결**: 위협모델 S/T(공급망), ADR 0010/0011
- **한 줄**: 나쁜 변경을 **머지 전에** 막는다 — 서명 변조·IaC 위반·만료 억제

### 시연 포인트 (이미 레포에 증거 존재)
1. **산출물 서명 변조** → `signing-tamper-test.yml`: 1바이트 변조 후 verify → 거부(exit 1).
2. **OIDC 경계** → `oidc-trust-boundary-test.yml`: 다른 repo sub 로 assume 시도 → deny.
3. **배포 롤 경계** → `deploy-role-boundary-test.yml`: 정책 밖 행위 → deny.
4. **라이브 IaC 게이트**(즉석 시연용): Checkov 위반을 일부러 넣은 PR 하나 →
   `iac/IaC 정책 (Checkov)` 가 빨간 X 로 머지 차단.

### 보여줄 화면
- 위 워크플로의 **녹색 체크**(통제가 공격을 거부함) 또는 라이브 PR 의 **빨간 X**.
- GitHub Actions 로그에서 "거부/실패" 라인.

### 서사 포인트
"런타임 탐지(A/B) 이전에, 애초에 나쁜 게 들어오지 못하게 막는 층을 두고
그것도 공격으로 검증했다. 9개 PR 게이트 + 3개 침투검증 워크플로."

---

## 데모 체크리스트

- [ ] 메일 수신 환경 준비(SNS 구독 confirmed)
- [ ] Demo A: 샘플 발사 → 메일 → 대응 → 아카이브
- [ ] Demo B: 설정 변경 → 알람 ALARM → (옵션2면 로깅 재개 확인)
- [ ] Demo C: 침투검증 워크플로 결과 또는 라이브 실패 PR
- [ ] 각 데모마다 "위협모델 어느 항목 / 런북 어느 절차"를 말로 연결

## 참고
- 위협모델: docs/threat-model.md · 런북: docs/runbook.md
- 검증 이력: docs/security-testing.md (Case 1–14)
- 트리아지: docs/prowler-triage.md
