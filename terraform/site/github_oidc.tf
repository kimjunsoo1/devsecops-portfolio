# ---------------------------------------------------------------------------
# GitHub Actions ↔ AWS 를 액세스 키 없이 연결합니다.
#
# 동작 방식:
#   1. 워크플로가 실행되면 GitHub 이 그 실행에 대한 JWT 를 발급합니다.
#      (리포지토리, 브랜치, 워크플로 이름 등이 클레임으로 들어 있음)
#   2. 워크플로가 그 JWT 를 들고 AWS STS 에 AssumeRoleWithWebIdentity 를 호출합니다.
#   3. AWS 는 아래 OIDC 제공자를 통해 서명을 검증하고,
#      역할의 신뢰 정책 조건과 JWT 클레임을 대조합니다.
#   4. 통과하면 1시간짜리 임시 자격증명을 내줍니다.
#
# 어디에도 저장되는 비밀 값이 없습니다.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # JWT 의 aud 클레임이 이 값이어야 합니다.
  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list 는 더 이상 필요하지 않습니다.
  # AWS 가 2023년부터 지문 대신 신뢰된 CA 목록으로 서버 인증서를 검증하고,
  # AWS 프로바이더 v5.81 부터 이 인자가 선택 사항이 되었습니다.
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    sid     = "GitHubActionsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # aud 검증. 이 조건이 없으면 다른 서비스용으로 발급된 토큰도 통과합니다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub 검증 — 여기가 핵심입니다.
    # StringLike 로 "repo:owner/*" 같이 느슨하게 열어두면
    # 내 다른 리포지토리, 심지어 포크된 리포지토리의 워크플로도 들어옵니다.
    # 리포지토리와 브랜치를 정확히 한 값으로 고정합니다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.deploy_branch}"
      ]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name        = "${var.project}-github-deploy"
  description = "GitHub Actions deploy role via OIDC - ${var.deploy_branch} branch only"

  assume_role_policy = data.aws_iam_policy_document.github_assume.json

  # 배포 작업은 몇 분이면 끝납니다. 길게 열어둘 이유가 없습니다.
  max_session_duration = 3600
}

# 지금은 권한을 하나도 주지 않았습니다.
# 권한이 없어도 sts:GetCallerIdentity 는 되기 때문에
# "인증이 되는가" 만 먼저 확인할 수 있습니다.
# 실제 배포 권한(S3 쓰기, CloudFront 무효화)은 모듈 4에서 붙입니다.
