########################################
# Random suffix for unique bucket names
########################################
resource "random_id" "rand" {
  byte_length = 4
}

########################################
# S3 Buckets
########################################
resource "aws_s3_bucket" "raw_data" {
  bucket        = "gym-usage-raw-data-${random_id.rand.hex}"
  force_destroy = true
}

resource "aws_s3_bucket" "reports" {
  bucket        = "gym-usage-reports-${random_id.rand.hex}"
  force_destroy = true
}



########################################
# IAM Role for ALL Lambdas
########################################
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_ingest_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Basic Lambda logging
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 access (broad; tighten later)
resource "aws_iam_role_policy_attachment" "lambda_s3_write" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Athena access (needed by report lambda)
resource "aws_iam_role_policy_attachment" "lambda_athena_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAthenaFullAccess"
}

########################################
# Lambda: Ingest Events (API → S3)
########################################
resource "aws_lambda_function" "ingest_lambda" {
  function_name = "gym-ingest-lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  runtime       = "python3.10"
  handler       = "handler.lambda_handler"
  timeout       = 10

  filename         = "${path.module}/../lambda/ingest_lambda/ingest.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/ingest_lambda/ingest.zip")

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.raw_data.bucket
    }
  }
}

########################################
# API Gateway REST API → Lambda Proxy
########################################
data "aws_region" "current" {}

resource "aws_api_gateway_rest_api" "api" {
  name        = "gym-ingest-api"
  description = "API to receive gym usage events"
}

resource "aws_api_gateway_resource" "event_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "event"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.event_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Correct Lambda proxy integration URI format:
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.event_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.ingest_lambda.arn}/invocations"
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "api_deploy" {
  depends_on  = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

########################################
# Glue Data Catalog (Athena metadata)
########################################
resource "aws_glue_catalog_database" "gymdb" {
  name = "gymdb"
}

resource "aws_glue_catalog_table" "gym_events" {
  name          = "gym_events"
  database_name = aws_glue_catalog_database.gymdb.name
  table_type    = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.raw_data.bucket}/raw/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "member_id"
      type = "string"
    }
    columns {
      name = "equipment_id"
      type = "string"
    }
    columns {
      name = "start_time"
      type = "string"
    }
    columns {
      name = "end_time"
      type = "string"
    }
    columns {
      name = "calories_burned"
      type = "int"
    }
    columns {
      name = "membership_expiry"
      type = "string"
    }
  }
}

########################################
# Lambda: Daily Report (Athena → CSV → S3)
########################################
resource "aws_lambda_function" "report_lambda" {
  function_name = "gym-daily-report"
  role          = aws_iam_role.lambda_exec_role.arn
  runtime       = "python3.10"
  handler       = "handler.lambda_handler"
  timeout       = 60

  filename         = "${path.module}/../lambda/report_lambda/report.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/report_lambda/report.zip")

  environment {
    variables = {
      DATABASE      = aws_glue_catalog_database.gymdb.name
      TABLE         = aws_glue_catalog_table.gym_events.name
      OUTPUT_BUCKET = aws_s3_bucket.reports.bucket
      EMAIL_FROM    = "mkssingh8600@gmail.com"
      EMAIL_TO      = "mkssingh8600@gmail.com"
    }
  }
}




########################################
# EventBridge Schedule → Report Lambda
########################################
resource "aws_cloudwatch_event_rule" "daily_report" {
  name                = "daily-report-schedule"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "daily_report_target" {
  rule      = aws_cloudwatch_event_rule.daily_report.name
  target_id = "ReportLambda"
  arn       = aws_lambda_function.report_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.report_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_report.arn
}
resource "aws_iam_role_policy_attachment" "lambda_ses_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

########################################
# Outputs
########################################
output "raw_bucket_name" {
  value = aws_s3_bucket.raw_data.bucket
}

output "reports_bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "api_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_deployment.api_deploy.stage_name}/event"
}
