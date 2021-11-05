# create zip of s3 reader lambda 
data "archive_file" "s3_reader_dynamodb_writer_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/s3_reader_dynamodb_writer_lambda.py"
  output_path = "${path.module}/lambdas/s3_reader_dynamodb_writer_lambda.zip"
}

# create zip of dynamodb reader lambda 
data "archive_file" "dynamodb_reader_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/dynamodb_reader_lambda.py"
  output_path = "${path.module}/lambdas/dynamodb_reader_lambda.zip"
}

# create zip of webhook lambda 
data "archive_file" "webhook_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambdas/webhook_lambda.py"
  output_path = "${path.module}/lambdas/webhook_lambda.zip"
}


# create zip of pandas for lambda layer
data "archive_file" "pandas_layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/layers/pandas"
  output_path = "${path.module}/layers/pandas/python.zip"
}