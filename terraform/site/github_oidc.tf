# ---------------------------------------------------------------------------
# GitHub Actions ↔ AWS 를 액세스 키 없이 연결합니다.
#
#   1. 워크플로가 실행되면 GitHub 이 그 실행에 대한 JWT 를 발급합니다.
#   2. 워크플로가 그 JWT 로 AWS STS 에 AssumeRoleWithWebIdentity 를 호출합니다.
#   3. AWS 가 서명을 검증하고, 역할의 신뢰 정책 조건과 JWT 클레임을 대조합니다.
#   4. 통과하면 1시간짜리 임시 자격증명을 내줍니다.
#
# 저장되는 비밀 값이 없습니다.
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # JWT 의 aud 클레임이 이 값이어야 합니다.
  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list 는 넣지 않습니다.
  # AWS 가 2023년부터 지문 대신 신뢰된 CA 목록으로 서버 인증서를 검증하고,
  # AWS 프로바이더 v5.81 부터 이 인자가 선택 사항이 되었습니다.
}

locals {
  # GitHub 이 보내는 sub 클레임을 그대로 구성합니다.
  # 이름 뒤의 숫자 ID 는 재사용되지 않는 불변 식별자입니다.
  github_subject = join("", [
    "repo:",
    "${var.github_owner}@${var.github_owner_id}",
    "/",
    "${var.github_repo}@${var.github_repo_id}",
    ":ref:refs/heads/${var.deploy_branch}",
  ])
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

    # aud 검증. 없으면 다른 용도로 발급된 GitHub 토큰도 통과합니다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub 검증 — 여기가 핵심입니다.
    #
    # StringLike 에 "repo:owner/*" 같이 쓰면 내 다른 리포지토리 전부가 들어옵니다.
    # "repo:owner/repo:*" 는 브랜치 제한이 없어서, 누가 워크플로를 수정해
    # 임의의 브랜치에서 실행하면 그대로 통과합니다.
    #
    # 여기서는 StringEquals 로 리포지토리와 브랜치를 정확히 한 값에 고정합니다.
    # 구 형식(이름만 있는 sub)은 일부러 허용하지 않습니다 —
    # 그걸 같이 열어두면 네임스페이스 재활용 공격 경로가 되살아납니다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_subject]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name = "${var.project}-github-deploy"

  # IAM description 은 ASCII/Latin-1 만 허용합니다. 한글을 넣으면 API 가 거부합니다.
  description = "GitHub Actions deploy role via OIDC - ${var.deploy_branch} branch only"

  assume_role_policy = data.aws_iam_policy_document.github_assume.json

  # 배포는 몇 분이면 끝납니다. 길게 열어둘 이유가 없습니다.
  max_session_duration = 3600
}

# 권한은 아직 하나도 붙이지 않았습니다.
# 권한이 없어도 sts:GetCallerIdentity 는 되므로 "인증이 되는가" 만 먼저 확인합니다.
# 실제 배포 권한(S3 쓰기, CloudFront 무효화)은 모듈 4 에서 붙입니다.
