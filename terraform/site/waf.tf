# ---------------------------------------------------------------------------
# CloudFront 앞단 WAF
#
# 왜 지금인가: .trivyignore.yaml 의 AWS-0011 유예가 2026-11-01 에 만료되어
# CI 게이트가 막혔습니다. 기한 장치가 "다시 판단하라" 고 물어온 것이고,
# 연장이나 영구 수용 대신 적용으로 답합니다.
#
# 리전 제약: CLOUDFRONT 스코프 Web ACL 은 us-east-1 에만 만들 수 있습니다.
# 그래서 provider = aws.us_east_1 이 필요하고, 그 프로바이더 별칭을
# versions.tf 에 되살렸습니다 (4주차 모듈 1 에서 미사용이라 지웠던 것).
#
# 비용: Web ACL $5 + 룰 3개 $3 + 요청 100만건당 $0.60.
# 월 약 $8 이고, 이 프로젝트에서 가장 비싼 단일 항목이 됩니다.
# 룰 그룹을 줄이면 깎을 수 있으므로 한 달 운영 후 재검토 대상입니다.
#
# 차단 모드 선택: 관리형 룰 그룹을 COUNT 로 먼저 돌려 오탐을 관찰한 뒤
# BLOCK 으로 올리는 것이 일반적인 절차입니다. 여기서는 처음부터 BLOCK
# 입니다 - 오리진이 정적 파일만 서빙하고 요청 본문도 쿼리 기반 로직도
# 없어서 관리형 룰이 오탐을 낼 표면이 거의 없습니다. 동적 애플리케이션
# 이라면 이 선택은 하지 않습니다.
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "site" {
  provider = aws.us_east_1

  name        = "${var.project}-site"
  description = "WAF for the static site CloudFront distribution"
  scope       = "CLOUDFRONT"

  # 기본은 허용입니다. 룰에 걸리는 것만 막습니다.
  # 정적 사이트를 기본 차단으로 두면 사이트가 안 보입니다.
  default_action {
    allow {}
  }

  # -------------------------------------------------------------------------
  # 1. 레이트 제한 — 비용 증폭 공격 대응
  #
  # 이 사이트에서 가장 현실적인 위협은 데이터 유출이 아니라 요청 폭주로
  # 인한 과금입니다. CloudFront 전송량과 WAF 요청 요금이 같이 늘어납니다.
  # 1주차 일/월 예산 알림이 사후에 알려주지만, 이 룰은 사전에 막습니다.
  #
  # 1000건/5분/IP 는 개인 포트폴리오에 넉넉한 값입니다. 정상 방문자가
  # 5분에 1000번 요청할 일은 없습니다. 운영 후 샘플 로그를 보고 조입니다.
  # -------------------------------------------------------------------------
  rule {
    name     = "rate-limit-per-ip"
    priority = 10

    action {
      block {
        # 공격 패턴 차단(관리형 룰)은 기본 403 을 쓰고, CloudFront 의
        # custom_error_response 가 그것을 404 로 덮습니다. 공격자에게
        # WAF 의 존재를 알려주지 않는 쪽이 낫고, 방어 측은 샘플 로그와
        # CloudWatch 메트릭으로 전부 봅니다.
        #
        # 레이트 제한은 다릅니다. 요청이 많아 막힌 클라이언트에게 404 를
        # 주면 "없다" 는 뜻이 되어 재시도를 멈출 이유가 없습니다. 429 는
        # custom_error_response 에 매핑이 없어 그대로 전달됩니다.
        custom_response {
          response_code = 429
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = 1000
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # 2. AWS 관리형 코어 룰셋
  #
  # OWASP Top 10 계열의 일반적인 패턴 - 경로 탐색, 로컬 파일 포함,
  # XSS, 비정상 요청 크기 등을 봅니다.
  # -------------------------------------------------------------------------
  rule {
    name     = "aws-managed-common"
    priority = 20

    # override_action none = 룰 그룹이 정한 동작(대부분 BLOCK)을 그대로 씁니다.
    # count {} 로 바꾸면 관찰 모드가 됩니다.
    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-managed-common"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------------------------
  # 3. AWS 관리형 Known Bad Inputs
  #
  # 알려진 악성 입력 패턴. Log4Shell(Log4JRCE) 룰이 여기 들어 있습니다.
  # Checkov CKV2_AWS_47 이 요구하는 것이 정확히 이 룰 그룹입니다.
  # -------------------------------------------------------------------------
  rule {
    name     = "aws-managed-known-bad-inputs"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-managed-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # sampled_requests_enabled = true 가 중요합니다. 차단된 요청의 샘플을
  # 콘솔과 API 로 볼 수 있게 해줍니다. 전체 WAF 로깅(별도 로그 그룹 +
  # us-east-1 전용 KMS 키)을 붙이지 않고도 "무엇이 왜 막혔는가" 를
  # 확인할 수 있어서, 지금 단계에서는 이걸로 충분합니다.
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-site"
    sampled_requests_enabled   = true
  }
}
