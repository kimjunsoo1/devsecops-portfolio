# Prowler 베이스라인 트리아지 (계정 전역 스캔)

/ 리전 `ap-northeast-2` · Prowler 전체 스캔 결과를 전수 분류한 문서.

## 요약

계정 전역 Prowler 스캔에서 **63개 고유 체크 FAIL** (Critical 1 / High 10 / Medium 33 / Low 19).
Checkov 인라인 억제와 동일 원칙을 적용했다 — **억제엔 반드시 분류 + 근거 + 기한**.

| 분류 | 의미 | 처리 | 건수 |
|---|---|---|---|
| **N/A** | 단일 계정 조직 / 미사용 서비스로 구조적 성립 불가 | mutelist (permanent) | 20 |
| **ACCEPT** | 개인 포트폴리오 범위에서 비용·운영상 의도적 미적용 | mutelist (permanent) | 23 |
| **REVISIT** | 할 수 있으나 보류, 기한 명시 | mutelist (revisit=2027-05-31) | 17 |
| **REMEDIATE** | 실제 수정 대상 — **억제하지 않음** | 백로그 (아래) | 3 |

억제 60건은 `prowler-mutelist.yaml`에 분류·근거·기한 주석으로 기록하고,
`scripts/check-prowler-mutelist.py`로 **기계 검증**한다(만료된 revisit은 실패 처리 → 재검토 강제).

## 수정 백로그 (억제하지 않음 — 의도적으로 노출)

진단/모의해킹 관점에서 가장 중요한 항목은 **숨기지 않고 추적**한다.

| 체크 | 심각도 | 내용 | 조치 |
|---|---|---|---|
| `iam_aws_attached_policy_no_administrative_privileges` | CRITICAL | `AdministratorAccess`(`*:*`)가 부착됨 | IAM Identity Center 권한셋 **최소권한화** (P1) |
| `iam_role_administratoraccess_policy` | HIGH | `AWSReservedSSO_AdministratorAccess` 롤에 Admin 정책 | 위와 동일 과제 — 업무별 권한셋 분리 |
| `accessanalyzer_enabled` | LOW | IAM Access Analyzer 미활성 | **무료** — 즉시 활성화 대상 (quick win) |

> CRITICAL/High의 Admin 접근 2건은 IAM Identity Center(SSO)에서 관리자가 쓰는 권한셋이다.
> 영구 억제로 숨기지 않고 **"최소권한 권한셋" 과제로 추적**한다 — 리뷰어에게 리스크 인지·관리
> 능력을 보여주는 쪽이 억제보다 낫다. Access Analyzer는 과금이 없어 다음 라운드에서 바로 켠다.

## 확인 필요 1건

- `cloudwatch_log_metric_filter_disable_or_scheduled_deletion_of_kms_cmk` — 우리 `audit-key-change`
  메트릭 필터(DisableKey/ScheduleKeyDeletion/PutKeyPolicy/DisableKeyRotation)가 **이미 커버**하는데
  Prowler가 FAIL로 본다. 필터 패턴과 Prowler 기대 패턴의 정합성을 다음 라운드에 확인한다.
  현재는 REVISIT로 분류(실제 통제는 존재하나 스캐너 인식 불일치 가능성).

## 적용·검증

```bash
# 억제 포맷 검증 (근거+기한 강제)
python3 scripts/check-prowler-mutelist.py

# mutelist 적용 스캔 — 억제분이 빠지고 REMEDIATE 3건만 남아야 함
prowler aws -f ap-northeast-2 --mutelist prowler-mutelist.yaml
```

## 원칙

- 억제는 "무시"가 아니라 **분류된 위험 수용**이다. 각 항목에 근거와, 영구/재검토 기한이 붙는다.
- `revisit` 기한이 지나면 검증 스크립트가 실패시켜 **재검토를 강제**한다 (썩지 않는 억제).
- 가장 위험한 항목(Admin 접근)은 억제 대상이 아니라 **추적 대상**이다.
