# ---------------------------------------------------------------------------
# GuardDuty — AWS 관리형 위협 탐지
#
# 4주차 CloudTrail 메트릭 알람은 우리가 "정의한 특정 이벤트"만 봤다. GuardDuty
# 는 우리가 정의하지 않은 위협 - 비정상 API 패턴, 탈취된 크리덴셜, 알려진
# 악성 IP, 크립토 마이닝 - 을 머신러닝과 위협 인텔로 탐지한다.
#
# 기본만 켠다. S3/Malware/Kubernetes/RDS/Lambda 보호 플랜은 끈다(비용).
# 우리 계정은 VPC 가 없어 Flow Logs/DNS 분석은 어차피 해당 없고, CloudTrail
# 관리 이벤트 분석이 중심이다. 1인 저트래픽 계정이라 월 $1~3, 첫 30일 무료.
#
# 발견사항은 EventBridge 를 거쳐 기존 SNS 토픽(4주차)으로 보낸다. 이것이
# 토픽 정책에 events.amazonaws.com 발행 허용을 추가해야 하는 이유다 -
# 4주차 ADR 0008 의 "키 정책 vs 토픽 정책" 과 같은 구조. 없으면 GuardDuty 가
# 탐지해도 메일이 오지 않는다.
# ---------------------------------------------------------------------------

resource "aws_guardduty_detector" "this" {
  #checkov:skip=CKV2_AWS_3:single-account AWS Organization, no delegated GuardDuty admin - org-wide config resources (organization_configuration/admin_account) are structurally N/A; detector is enabled directly in this account permanent
  enable = true

  # 발견사항 게시 주기. 15분이 최소(기본 6시간). 1인 계정이라 빠른 쪽.
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  # datasources / features 블록을 비워 기본 데이터 소스만 쓴다.
  # 보호 플랜(S3/Malware 등)을 명시적으로 켜지 않으면 과금되지 않는다.
}

# ---------------------------------------------------------------------------
# 발견사항 → EventBridge → SNS
#
# 심각도 4.0 이상(Medium/High)만 알림한다. GuardDuty 는 Low(0.1~3.9)를 꽤
# 내는데, 1인 계정에서 전부 메일받으면 노이즈가 되어 사람이 무시하게 된다
# (4주차 "임계값 1이면 무시한다"와 같은 판단). Low 는 콘솔에 쌓이되 메일은
# Medium 이상만.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.project}-guardduty-findings"
  description = "GuardDuty Medium/High 발견사항을 SNS 로 보낸다"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4.0] }]
    }
  })
}

# 원시 GuardDuty JSON 은 거대해서 메일로 그대로 오면 못 읽는다.
# input_transformer 로 타입·심각도·리전·설명만 요약한다.
resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "guardduty-to-sns"
  arn       = aws_sns_topic.billing_alerts.arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      region      = "$.detail.region"
      account     = "$.detail.accountId"
      title       = "$.detail.title"
      description = "$.detail.description"
    }
    # 따옴표가 포함된 한 줄 메시지. GuardDuty 발견사항 요약.
    input_template = <<EOT
"[GuardDuty] 심각도 <severity> | <type>"
"리전: <region>  계정: <account>"
"제목: <title>"
"설명: <description>"
"콘솔에서 전체 내용을 확인하세요: https://console.aws.amazon.com/guardduty/home?region=<region>#/findings"
EOT
  }
}

output "guardduty_detector_id" {
  description = "GuardDuty 디텍터 ID. 무료 체험 일수 조회 등에 쓴다."
  value       = aws_guardduty_detector.this.id
}
