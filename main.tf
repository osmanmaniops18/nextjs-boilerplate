

  # Create ECR Repository
  resource "aws_ecr_repository" "nest_repo" {
    name                 = "nest-repo"
    image_tag_mutability = "MUTABLE"
    image_scanning_configuration {
      scan_on_push = true
    }
  }

  # Lambda Role with necessary permissions
  resource "aws_iam_role" "lambda_role" {
    name = "lambda-execution-role"
    
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

  # Attach AWS Lambda basic execution role policy to the role
  resource "aws_iam_role_policy_attachment" "lambda_basic_execution_role" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  }

  # Build, Tag, and Push Docker Image to ECR
  resource "null_resource" "docker_build_push" {
    depends_on = [aws_ecr_repository.nest_repo]
    
    provisioner "local-exec" {
      command = <<EOT
        aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.nest_repo.repository_url}
        docker build -t nest-repo .
        docker tag nest-repo:latest ${aws_ecr_repository.nest_repo.repository_url}:latest
        docker push ${aws_ecr_repository.nest_repo.repository_url}:latest
      EOT
    }
    # This will cause the Docker image to be rebuilt and pushed every time the code changes
    triggers = {
      build_id = "${timestamp()}"  # This ensures the build is triggered every time
    }
  }

  # Lambda function
resource "aws_lambda_function" "nest_lambda" {
  function_name = "nest-lambda-function"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.nest_repo.repository_url}:latest"
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      FILE_DRIVER  = "local"         # Example environment variable
      DATABASE_URL = "postgresql://postgres.bzuonojmmutmofjufaym:af2Vo6HwYpSwGwmj@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres"
    }
  }

  depends_on = [null_resource.docker_build_push]
}


  # ECR Policy allowing Lambda to pull images from ECR
  resource "aws_ecr_repository_policy" "repo_policy" {
    repository = aws_ecr_repository.nest_repo.name

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Sid       = "LambdaPull",
          Effect    = "Allow",
          Principal = {
            Service = "lambda.amazonaws.com"
          },
          Action = [
            "ecr:GetDownloadUrlForLayer",
            "ecr:BatchGetImage",
            "ecr:BatchCheckLayerAvailability"
          ]
        }
      ]
    })
  }

  # API Gateway to trigger Lambda function
  resource "aws_apigatewayv2_api" "api" {
    name          = "NestJS API"
    protocol_type = "HTTP"
  }

  # Lambda integration with API Gateway
  resource "aws_apigatewayv2_integration" "lambda_integration" {
    api_id           = aws_apigatewayv2_api.api.id
    integration_type = "AWS_PROXY"
    integration_uri  = aws_lambda_function.nest_lambda.invoke_arn
  }

  # Create a route for the API Gateway
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /{proxy+}"  # This allows all routes and methods to be proxied to Lambda
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}


  # Create a stage for deployment (e.g., "prod")
  resource "aws_apigatewayv2_stage" "api_stage" {
    api_id      = aws_apigatewayv2_api.api.id
    name        = "prod"
    auto_deploy = true
  }

  # Give API Gateway permission to invoke the Lambda function
  resource "aws_lambda_permission" "apigw_lambda_permission" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.nest_lambda.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
  }

  # Output the API endpoint for testing
  output "api_endpoint" {
    value = "${aws_apigatewayv2_stage.api_stage.invoke_url}"
  }
