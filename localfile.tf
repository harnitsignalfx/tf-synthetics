resource "local_file" "urlfile" {
    content     = "https://www.yahoo.com"
    filename = "${path.module}/python-syn/urlfile"
}

data "archive_file" "init" {
  type        = "zip"
  source_dir = "${path.module}/python-syn"
  output_path = "${path.module}/output-zip/python-syn.zip"

  depends_on = [
    local_file.urlfile
  ]
}

# Specify the provider and access details
provider "aws" {
	profile = "default"
	region = "us-east-1"
}

data "aws_iam_policy_document" "policy" {
  statement {
    sid    = ""
    effect = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = format("%s_%s","iam_for_lambda",replace(replace(local_file.urlfile.content,"https://",""),".","_"))
  assume_role_policy = data.aws_iam_policy_document.policy.json
}

resource "aws_lambda_function" "syn_lambda" {
  function_name = format("%s_%s","syn_check_lambda",replace(replace(local_file.urlfile.content,"https://",""),".","_"))

  filename         = data.archive_file.init.output_path
  source_code_hash = data.archive_file.init.output_base64sha256

  role    = aws_iam_role.iam_for_lambda.arn
  handler = "pythonLambda.request_handler"
  runtime = "python3.6"
  timeout = 10

  environment {
    variables = {
      SIGNALFX_ACCESS_TOKEN = "RAdoUbMMBeRLp2IEOm52Fg"
      SIGNALFX_ENDPOINT_URL = "https://ingest.signalfx.com"
    }
  }
}

resource "aws_cloudwatch_event_rule" "every_one_minute" {
    name = format("%s_%s","every-minute",replace(replace(local_file.urlfile.content,"https://",""),".","_"))
    description = "Fires every minute"
    schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "syn_lambda_every_one_minute" {
    rule = aws_cloudwatch_event_rule.every_one_minute.name
    target_id = "syn_lambda"
    arn = aws_lambda_function.syn_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_syn_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.syn_lambda.function_name
    principal = "events.amazonaws.com"
    source_arn = aws_cloudwatch_event_rule.every_one_minute.arn
}