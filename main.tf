terraform {
  backend "remote" {
    organization = "practice-terraform-craftsmen"
    workspaces {
      name = "Example-Workspace"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# resource "aws_instance" "app_server" {
#   ami           = "ami-02e136e904f3da870"
#   instance_type = "t2.micro"

#   tags = {
#     Name = var.instance_name
#   }
# }

# SNS topic 
resource "aws_sns_topic" "terraform_topic" {
  name = "s3-event-notification-topic"

  policy = <<POLICY
{
    "Version":"2012-10-17",
    "Statement":[{
        "Effect": "Allow",
        "Principal": { "Service": "s3.amazonaws.com" },
        "Action": "SNS:Publish",
        "Resource": "arn:aws:sns:*:*:s3-event-notification-topic",
        "Condition":{
            "ArnLike":{"aws:SourceArn":"${aws_s3_bucket.terraform_s3_bucket.arn}"}
        }
    }]
}
POLICY

}


resource "aws_sqs_queue" "terraform_queue_deadletter" {
  name = "deadletter-queue"
  tags = {
    Environment = "dev"
  }
}

resource "aws_sqs_queue" "terraform_queue" {
  name                      = "primary-queue"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.terraform_queue_deadletter.arn
    maxReceiveCount     = 4
  })

  tags = {
    Environment = "dev"
  }
}

resource "aws_sqs_queue_policy" "terraform_sqs_access_policy" {
  queue_url = aws_sqs_queue.terraform_queue.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Effect": "Allow",
       "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "${aws_sqs_queue.terraform_queue.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_sns_topic.terraform_topic.arn}"
        }
      }
    }
  ]
}
POLICY
}


resource "aws_sns_topic_subscription" "csv_uploaded_sqs_target" {
  topic_arn = aws_sns_topic.terraform_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.terraform_queue.arn
}


resource "aws_s3_bucket" "terraform_s3_bucket" {
  bucket = "my-craftsmen-s3-bucket"
}

resource "aws_s3_bucket_notification" "terraform_s3_bucket_notification" {
  bucket = aws_s3_bucket.terraform_s3_bucket.id

  topic {
    topic_arn     = aws_sns_topic.terraform_topic.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".csv"
  }
}


resource "aws_lambda_layer_version" "pandas_lambda_layer" {
  filename                 = data.archive_file.pandas_layer_zip.output_path
  layer_name               = "MyLambda-Python37-Pandas3x"
  compatible_runtimes      = ["python3.7"]
  compatible_architectures = ["x86_64"]
}

resource "aws_iam_policy" "policy_reading_s3_writing_to_dynamodb" {
  name        = "policy_reading_s3_writing_to_dynamodb"
  description = "Access to read s3 files and write to dynamodb"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ConsoleAccess",
        "Effect" : "Allow",
        "Action" : [
          "s3:GetAccountPublicAccessBlock",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:GetBucketPolicyStatus",
          "s3:GetBucketPublicAccessBlock",
          "s3:ListAllMyBuckets"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "ListObjectsInBucket",
        "Effect" : "Allow",
        "Action" : "s3:ListBucket",
        "Resource" : ["${aws_s3_bucket.terraform_s3_bucket.arn}"]
      },
      {
        "Sid" : "AllObjectActions",
        "Effect" : "Allow",
        "Action" : "s3:*Object",
        "Resource" : ["${aws_s3_bucket.terraform_s3_bucket.arn}/*"]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        "Resource" : "${aws_dynamodb_table.my_csv_store.arn}"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sqs:*"
        ],
        "Resource" : "${aws_sqs_queue.terraform_queue.arn}"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        "Resource" : [
          "arn:aws:logs:*:*:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "iam_for_reading_s3_writing_to_dynamodb" {
  name = "iam_for_reading_s3_writing_to_dynamodb"

  assume_role_policy = jsonencode({

    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Effect" : "Allow",
        "Sid" : ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_to_dynamodb_lambda_policy_attachment" {
  role       = aws_iam_role.iam_for_reading_s3_writing_to_dynamodb.name
  policy_arn = aws_iam_policy.policy_reading_s3_writing_to_dynamodb.arn
}

resource "aws_lambda_function" "s3_reader_dynamodb_writer_lambda" {
  filename      = data.archive_file.s3_reader_dynamodb_writer_lambda_zip.output_path
  function_name = "s3_reader_dynamodb_writer_lambda_function"
  role          = aws_iam_role.iam_for_reading_s3_writing_to_dynamodb.arn
  handler       = "s3_reader_dynamodb_writer_lambda.s3_lambda_handler"

  source_code_hash = data.archive_file.s3_reader_dynamodb_writer_lambda_zip.output_base64sha256

  layers        = ["${aws_lambda_layer_version.pandas_lambda_layer.arn}", "arn:aws:lambda:us-east-1:668099181075:layer:AWSLambda-Python37-SciPy1x:37"]
  runtime       = "python3.7"
  architectures = ["x86_64"]
  environment {
    variables = {
      "REGION"     = "us-east-1"
      "TABLE_NAME" = "my_csv_store"
    }
  }
  timeout = 300
}

resource "aws_cloudwatch_log_group" "s3_reader_dynamodb_writer_lambda_loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.s3_reader_dynamodb_writer_lambda.function_name}"
  retention_in_days = 1
}


resource "aws_lambda_event_source_mapping" "read_sqs_s3_message" {
  event_source_arn                   = aws_sqs_queue.terraform_queue.arn
  function_name                      = aws_lambda_function.s3_reader_dynamodb_writer_lambda.arn
  batch_size                         = 1
  maximum_batching_window_in_seconds = 20

}

# # # Dynamodb table for storing csv data
resource "aws_dynamodb_table" "my_csv_store" {
  name             = "my_csv_store"
  billing_mode     = "PROVISIONED"
  read_capacity    = 20
  write_capacity   = 20
  hash_key         = "email"
  range_key        = "gender"
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  attribute {
    name = "email"
    type = "S"
  }

  attribute {
    name = "gender"
    type = "S"
  }
}





# IAM for reading dynamodb
resource "aws_iam_role" "iam_for_reading_dynamodb" {
  name = "iam_for_reading_dynamodb"

  assume_role_policy = jsonencode({

    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Effect" : "Allow",
        "Sid" : ""
      }
    ]
  })
}


resource "aws_iam_policy" "policy_for_reading_dynamodb" {
  name        = "policy_for_reading_dynamodb"
  description = "Access to the dynamodb"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "lambda:InvokeFunction",
        "Resource" : "${aws_lambda_function.lambda_for_reading_dynamodb.arn}"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:BatchGetItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        "Resource" : [
          "${aws_dynamodb_table.my_csv_store.arn}"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams",
          "dynamodb:ListShards"
        ],
        "Resource" : [
          "${aws_dynamodb_table.my_csv_store.stream_arn}"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        "Resource" : [
          "arn:aws:logs:*:*:*"
        ]
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.iam_for_reading_dynamodb.name
  policy_arn = aws_iam_policy.policy_for_reading_dynamodb.arn
}

resource "aws_lambda_function" "lambda_for_reading_dynamodb" {
  filename      = data.archive_file.dynamodb_reader_lambda_zip.output_path
  function_name = "my_dynamodb_reader"
  role          = aws_iam_role.iam_for_reading_dynamodb.arn
  handler       = "dynamodb_reader_lambda.dynamodb_lambda_handler"

  source_code_hash = data.archive_file.dynamodb_reader_lambda_zip.output_base64sha256

  runtime = "python3.7"
  environment {
    variables = { 
      "API_URL" = "${aws_api_gateway_deployment.my_rest_api_deployment.invoke_url}${aws_api_gateway_stage.stage_dev.stage_name}${aws_api_gateway_resource.resource_add_data.path}"
    }
  }
  timeout = 300
}

resource "aws_lambda_event_source_mapping" "dynamodb_on_new_item" {
  event_source_arn  = aws_dynamodb_table.my_csv_store.stream_arn
  function_name     = aws_lambda_function.lambda_for_reading_dynamodb.arn
  starting_position = "LATEST"
  
}

resource "aws_cloudwatch_log_group" "dynamodb_reader_lambda_loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_for_reading_dynamodb.function_name}"
  retention_in_days = 1
}

resource "aws_iam_role" "iam_for_webhook_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "policy_for_writing_log" {
  name        = "policy_for_writing_log"
  description = "Write log to the cloud-watch"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [ 
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        "Resource" : [
          "arn:aws:logs:*:*:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "webhook_role_policy_attachment" {
  role       = aws_iam_role.iam_for_webhook_lambda.name
  policy_arn = aws_iam_policy.policy_for_writing_log.arn
}

resource "aws_cloudwatch_log_group" "webhook_lambda_loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.webhook_lambda.function_name}"
  retention_in_days = 1
}
resource "aws_lambda_function" "webhook_lambda" {
  filename         = data.archive_file.webhook_lambda_zip.output_path
  function_name    = "webhook_lambda_function"
  handler          = "webhook_lambda.webhook_lambda_handler"
  role             = aws_iam_role.iam_for_webhook_lambda.arn
  source_code_hash = data.archive_file.webhook_lambda_zip.output_base64sha256

  runtime = "python3.7"
}

# API Gateway
resource "aws_api_gateway_rest_api" "my_rest_api" {
  name = "rest_webhook"

}

resource "aws_api_gateway_resource" "resource_add_data" {
  path_part   = "add_data"
  parent_id   = aws_api_gateway_rest_api.my_rest_api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.my_rest_api.id
}

resource "aws_api_gateway_method" "method_post" {
  rest_api_id   = aws_api_gateway_rest_api.my_rest_api.id
  resource_id   = aws_api_gateway_resource.resource_add_data.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.my_rest_api.id
  resource_id             = aws_api_gateway_resource.resource_add_data.id
  http_method             = aws_api_gateway_method.method_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webhook_lambda.invoke_arn
}

# resource "aws_api_gateway_method_response" "response_200" {
#   rest_api_id = aws_api_gateway_rest_api.my_rest_api.id
#   resource_id = aws_api_gateway_resource.resource_add_data.id
#   http_method = aws_api_gateway_method.method_post.http_method
#   response_models = {
#     "application/json" = "Empty"
#   }
#   status_code = "200"
# }

# resource "aws_api_gateway_integration_response" "integration_response_200" {
#   rest_api_id = aws_api_gateway_rest_api.my_rest_api.id
#   resource_id = aws_api_gateway_resource.resource_add_data.id
#   http_method = aws_api_gateway_method.method_post.http_method
#   status_code = aws_api_gateway_method_response.response_200.status_code

#   # Transforms the backend JSON response to XML
#   response_templates = {
#     "application/json" = ""
#   }
# }

resource "aws_api_gateway_deployment" "my_rest_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.my_rest_api.id
  depends_on = [
    aws_api_gateway_method.method_post,
    aws_api_gateway_integration.integration_lambda
  ]
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.my_rest_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage_dev" {
  deployment_id = aws_api_gateway_deployment.my_rest_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.my_rest_api.id
  stage_name    = "dev"
}

# Lambda permission
resource "aws_lambda_permission" "apigw_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.webhook_lambda.function_name}"
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.my_rest_api.execution_arn}/*/*"
}

