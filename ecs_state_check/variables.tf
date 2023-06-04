variable "slack_webhook_url" {
  type = string
}

variable "all_account_root_arns" {
  type = list(string)
}

variable "all_account_ids" {
  type = map(string)
}