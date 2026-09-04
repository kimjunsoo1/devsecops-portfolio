variable "project" {
  description = "리소스 이름 접두사로 쓰이는 프로젝트 슬러그"
  type        = string
  default     = "devsecops-portfolio"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project))
    error_message = "project 는 소문자/숫자/하이픈 3~32자여야 합니다."
  }
}

variable "aws_region" {
  description = "기본 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "owner" {
  description = "Owner 태그 값 (본인 GitHub 아이디 등)"
  type        = string
}
