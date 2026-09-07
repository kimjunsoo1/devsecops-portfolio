variable "project" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "devsecops-portfolio"
}

variable "aws_region" {
  description = "기본 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "owner" {
  description = "Owner 태그 값"
  type        = string
}

variable "github_owner" {
  description = "GitHub 사용자 또는 조직 이름"
  type        = string
}

variable "github_repo" {
  description = "GitHub 리포지토리 이름"
  type        = string
}

# --- OIDC sub 클레임의 불변 식별자 ---------------------------------------
# 2026-07-15 이후 만들어진 리포지토리는 sub 클레임에 숫자 ID 가 포함됩니다.
#   repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/<branch>
# 이름은 바뀔 수 있지만 ID 는 재사용되지 않기 때문에,
# 계정을 지우고 같은 이름으로 다시 만드는 방식의 위장이 불가능합니다.
#
#   gh api /users/<owner> --jq .id
#   gh api /repos/<owner>/<repo> --jq .id

variable "github_owner_id" {
  description = "GitHub 소유자의 숫자 ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "숫자만 입력하세요. gh api /users/<owner> --jq .id 로 확인합니다."
  }
}

variable "github_repo_id" {
  description = "GitHub 리포지토리의 숫자 ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repo_id))
    error_message = "숫자만 입력하세요. gh api /repos/<owner>/<repo> --jq .id 로 확인합니다."
  }
}

variable "deploy_branch" {
  description = "배포를 허용할 브랜치. 이 브랜치의 워크플로만 역할을 assume 할 수 있습니다."
  type        = string
  default     = "main"
}
