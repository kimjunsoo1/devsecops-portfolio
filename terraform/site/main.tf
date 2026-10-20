data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  common_tags = {
    Project   = var.project
    Component = "site"
    ManagedBy = "terraform"
    Owner     = var.owner
  }
}
