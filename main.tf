terraform {
  cloud {
    hostname     = "app.terraform.io"
    organization = "organization-name"

    workspaces {
      name = "tools"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 1.3"
    }
  }
  required_version = ">= 0.13"
}

provider "aws" {
  region = "eu-central-1"
}

module "ecs_state_check" {
  source = "./modules/ecs_state_check"

  all_account_root_arns = local.all_account_root_arns
  all_account_ids       = local.all_account_ids
  slack_webhook_url     = var.ecs_sc_slack_webhook_url
}
