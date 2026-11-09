resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "lambda-role-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "ecs_permissions" {
  name        = "ecs-permissions-${var.environment}"
  description = "Permisos necesarios para la función Lambda que actualiza ECS."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "LeerYActualizarServiciosDelCluster"
        Effect   = "Allow",
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"],
        Resource = ["${replace(var.ecs_cluster, ":cluster/", ":service/")}/*"]
      },
      {
        Sid      = "LeerElCluster"
        Effect   = "Allow",
        Action   = ["ecs:DescribeClusters"],
        Resource = [var.ecs_cluster]
      },
      {
        Sid      = "ListarServiciosDelCluster"
        Effect   = "Allow",
        Action   = ["ecs:ListServices"],
        Resource = ["*"],
        Condition = {
          ArnEquals = { "ecs:cluster" = var.ecs_cluster }
        }
      },
      {
        # RegisterTaskDefinition no admite permisos a nivel de recurso.
        Sid      = "RegistrarTaskDefinitions"
        Effect   = "Allow",
        Action   = ["ecs:RegisterTaskDefinition"],
        Resource = ["*"]
      },
      {
        Sid      = "PasarSoloLosRolesDeLasTareas"
        Effect   = "Allow",
        Action   = ["iam:PassRole"],
        Resource = [var.execution_role_arn, var.task_role_arn],
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "xray_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.ecs_permissions.arn
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "update_deploy_lambda" {
  #checkov:skip=CKV_AWS_116:EventBridge reintenta la invocación; una DLQ en SQS queda fuera del alcance del laboratorio.
  #checkov:skip=CKV_AWS_117:La función solo llama a la API de ECS; ponerla en la VPC exigiría endpoints o NAT sin mejorar el aislamiento.
  #checkov:skip=CKV_AWS_173:Las variables de entorno no contienen secretos, solo nombres y ARN; se cifran con la llave administrada por AWS.
  #checkov:skip=CKV_AWS_272:El código se despliega desde este repositorio con Terraform; la firma de código con AWS Signer queda fuera del laboratorio.
  function_name = "update-deploy-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  reserved_concurrent_executions = 2

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ECS_CLUSTER     = var.ecs_cluster
      ENVIRONMENT     = var.environment
      EXECUTION_ROLE  = var.execution_role_arn
      TASK_ROLE       = var.task_role_arn
      REPOSITORIO_ECR = var.repositorio_ecr
    }
  }

  tags = {
    Name = "update-deploy-${var.environment}"
  }
}

resource "aws_cloudwatch_event_rule" "ecr_push_rule" {
  name        = "ecr-push-rule-${var.environment}"
  description = "Trigger Lambda on ECR image push"
  event_pattern = jsonencode({
    "source" : ["aws.ecr"],
    "detail-type" : ["ECR Image Action"],
    "detail" : {
      "action-type" : ["PUSH"],
      "result" : ["SUCCESS"],
      "repository-name" : [var.app1_image, var.app2_image],
      "image-tag" : [var.image_tag]
    }
  })
}


resource "aws_cloudwatch_event_target" "ecr_push_lambda_target" {
  rule      = aws_cloudwatch_event_rule.ecr_push_rule.name
  target_id = "lambda-target"
  arn       = aws_lambda_function.update_deploy_lambda.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_deploy_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_push_rule.arn
}
