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

variable "deploy_branch" {
  description = "배포를 허용할 브랜치. 이 브랜치의 워크플로만 역할을 assume 할 수 있습니다."
  type        = string
  default     = "main"
}
