# AWS events comes to default event bus. We defined a rule (and a role) to catch the events we want and gave our custom bus as a target (in aws_cloudwatch_event_target). 
# After that our custom bus calls own target (lambda function).  

resource "aws_cloudwatch_event_rule" "default_bus" {
  name           = "ecs-state-check"
  event_bus_name = "default"
  event_pattern  = <<EOF
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
#"ECS Container Instance State Change" can be added to detail-types

resource "aws_cloudwatch_event_target" "default_bus" {
  target_id = "ecs-sc-target-default"
  arn       = aws_cloudwatch_event_bus.this.arn
  rule      = aws_cloudwatch_event_rule.default_bus.name
  role_arn  = aws_iam_role.default_bus_target.arn
}

# IAM role for event bus target
data "aws_iam_policy_document" "events_assume" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "events.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "default_bus_target" {
  name = "ecs-sc-target-role"

  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "put_events" {
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.this.arn]
  }
}

resource "aws_iam_role_policy" "put_events" {
  name   = "put_events_policy"
  role   = aws_iam_role.default_bus_target.name
  policy = data.aws_iam_policy_document.put_events.json
}

######################################################################


resource "aws_cloudwatch_event_bus" "this" {
  name = "ecs-state-check"
}

resource "aws_cloudwatch_event_rule" "this" {
  name           = "ecs-state-check"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  event_pattern  = <<EOF
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

#"ECS Container Instance State Change" can be added to detail-types

resource "aws_cloudwatch_event_target" "this" {
  target_id      = "ecs-sc-target"
  arn            = aws_lambda_function.this.arn
  rule           = aws_cloudwatch_event_rule.this.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
}

data "aws_iam_policy_document" "cross_account_put_events" {
  statement {
    sid    = "EnvAccess"
    effect = "Allow"
    actions = [
      "events:PutEvents"
    ]
    resources = [aws_cloudwatch_event_bus.this.arn]
    principals {
      type        = "AWS"
      identifiers = var.all_account_root_arns

    }
  }
}

resource "aws_cloudwatch_event_bus_policy" "this" {
  policy         = data.aws_iam_policy_document.cross_account_put_events.json
  event_bus_name = aws_cloudwatch_event_bus.this.name
}

######################################################################

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/ecs-state-check"
  retention_in_days = 7
}

# IAM role for Lambda

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com"
      ]
    }
  }
}


resource "aws_iam_role" "this" {
  name = "ecs-sc-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}


data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarms",
      "iam:ListAccountAliases"
    ]
    resources = ["*"]
  }

}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:DescribeTasks",
      "iam:ListAccountAliases",
      "organizations:ListAccounts",
      "organizations:DescribeAccount"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [for account_id in var.all_account_ids : "arn:aws:iam::${account_id}:role/ecs-api-access-cross-account-role"]
  }
}

# Lambda
resource "aws_lambda_function" "this" {
  filename         = data.archive_file.this.output_path
  function_name    = "ecs-state-check"
  runtime          = "python3.9"
  handler          = "ecs_state_check.lambda_handler"
  role             = aws_iam_role.this.arn
  source_code_hash = data.archive_file.this.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }
}

# Trigger
resource "aws_lambda_permission" "this" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn

}

data "archive_file" "this" {
  type        = "zip"
  source_file = "${path.module}/lambda/ecs_state_check.py"
  output_path = "ecs_state_check.zip"
}
