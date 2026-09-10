# ---------------------------------------------------------------------------
# 침투 테스트용 취약 설정. apply 하지 마세요.
#
# Trivy misconfig 스캐너가 HIGH/CRITICAL 로 잡아야 합니다.
# 잡지 못하면 우리 게이트에 구멍이 있다는 뜻입니다.
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# 퍼블릭 읽기가 가능한 버킷. 암호화도 버전 관리도 없음.
resource "aws_s3_bucket" "insecure_demo" {
  bucket = "devsecops-portfolio-insecure-demo"
}

resource "aws_s3_bucket_public_access_block" "insecure_demo" {
  bucket = aws_s3_bucket.insecure_demo.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 전 세계에서 SSH 접속 가능한 보안그룹.
resource "aws_security_group" "insecure_demo" {
  name        = "insecure-demo"
  description = "Deliberately insecure - test fixture only"

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
