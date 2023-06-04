
locals {
  ecs_state_check_bus_arn = "arn:aws:events:eu-central-1:131605153677:event-bus/ecs-state-check"
}

resource "aws_cloudwatch_event_rule" "ecs_state_check_rule" {
  name          = "ecs-state-check"
  description   = "Captures ECS State Check Events"
  event_pattern = <<EOF
{
  "source": [
    "aws.ecs"
  ],
  "detail-type": [
    "ECS Task State Change"
  ]
}
EOF
}

resource "aws_cloudwatch_event_target" "ecs_state_check_target" {
  target_id = "ecs-sc-target-cross-account"
  arn       = local.ecs_state_check_bus_arn
  rule      = aws_cloudwatch_event_rule.ecs_state_check_rule.name
  role_arn  = aws_iam_role.ecs_state_check_cross_account.arn
}

resource "aws_iam_role" "ecs_state_check_cross_account" {
  name               = "ecs-state-check-cross-account-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_state_check.json
}

data "aws_iam_policy_document" "ecs_state_check" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy" "ecs_state_check_policy" {
  name   = "ecs-state-check-rule-perms"
  role   = aws_iam_role.ecs_state_check_cross_account.id
  policy = data.aws_iam_policy_document.ecs_state_check_policy_doc.json
}

data "aws_iam_policy_document" "ecs_state_check_policy_doc" {
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [local.ecs_state_check_bus_arn]
  }
}

###########################################

###  Role for Cross Account API Usage  ###

###########################################

resource "aws_iam_role" "ecs_api_access_cross_account" {
  name               = "ecs-api-access-cross-account-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_api_access_cross_account.json
}

data "aws_iam_policy_document" "ecs_api_access_cross_account" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::131605153677:role/ecs-sc-role"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy" "ecs_api_access_cross_account_policy" {
  name   = "ecs-api-rule-perms"
  role   = aws_iam_role.ecs_api_access_cross_account.id
  policy = data.aws_iam_policy_document.ecs_api_access_cross_account_doc.json
}

data "aws_iam_policy_document" "ecs_api_access_cross_account_doc" {
  statement {
    effect    = "Allow"
    actions   = ["ecs:DescribeTasks"]
    resources = ["*"]
  }
}