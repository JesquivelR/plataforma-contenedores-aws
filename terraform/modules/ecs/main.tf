resource "aws_ecs_cluster" "this" {
  name = "${var.environment}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "app1" {
  family                   = "${var.environment}-${var.app1_image}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "3072"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name                   = var.app1_image
      image                  = "${var.repositorio_ecr}/${var.app1_image}:${var.image_tag}"
      essential              = true
      readonlyRootFilesystem = true
      portMappings = [
        {
          name          = "${var.app1_image}-8000-tcp"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        {
          name  = "ENV"
          value = var.environment
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.environment}-${var.app1_image}"
          "awslogs-region"        = var.aws_region
          "awslogs-create-group"  = "true"
          "awslogs-stream-prefix" = "ecs"
          "mode"                  = "non-blocking"
          "max-buffer-size"       = "25m"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app1" {
  name            = "${var.environment}-${var.app1_image}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app1.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnets
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.app1_target_group_arn
    container_name   = var.app1_image
    container_port   = 8000
  }

}

resource "aws_ecs_task_definition" "app2" {
  family                   = "${var.environment}-${var.app2_image}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name                   = var.app2_image
      image                  = "${var.repositorio_ecr}/${var.app2_image}:${var.image_tag}"
      readonlyRootFilesystem = true
      portMappings = [
        {
          name          = "${var.app2_image}-8000-tcp"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      environment = [
        {
          name  = "ENV"
          value = var.environment
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.environment}-${var.app2_image}"
          "awslogs-region"        = var.aws_region
          "awslogs-create-group"  = "true"
          "awslogs-stream-prefix" = "ecs"
          "mode"                  = "non-blocking"
          "max-buffer-size"       = "25m"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app2" {
  name            = "${var.environment}-${var.app2_image}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app2.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnets
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.app2_target_group_arn
    container_name   = var.app2_image
    container_port   = 8000
  }

}