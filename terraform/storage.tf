# DynamoDB table for API metrics (time-series data)
resource "aws_dynamodb_table" "api_metrics" {
  name           = "${local.project_name}-api-metrics"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "endpoint"
  range_key      = "timestamp"

  attribute {
    name = "endpoint"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-api-metrics"
  })
}
