resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_150:Laboratorio: la protección contra borrado se deja apagada para poder destruir el entorno con terraform destroy.
  #checkov:skip=CKV_AWS_91:Los access logs necesitan un bucket S3 dedicado; quedan fuera del laboratorio por costo.
  #checkov:skip=CKV2_AWS_28:WAF tiene costo mensual fijo; en producción se asocia un web ACL al ALB.
  #checkov:skip=CKV2_AWS_20:Sin dominio ni certificado no hay listener HTTPS al cual redirigir.
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnets

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "app1" {
  #checkov:skip=CKV_AWS_378:El TLS termina en el ALB; el tráfico hacia las tareas viaja por subredes privadas.
  name        = "${var.environment}-${var.app1_image}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http-app1" {
  #checkov:skip=CKV_AWS_2:Sin dominio ni certificado de ACM el listener es HTTP.
  #checkov:skip=CKV_AWS_103:No aplica a un listener HTTP; se cumple al agregar HTTPS con una política TLS 1.2.
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app1.arn
  }
}

resource "aws_lb_target_group" "app2" {
  #checkov:skip=CKV_AWS_378:El TLS termina en el ALB; el tráfico hacia las tareas viaja por subredes privadas.
  name        = "${var.environment}-${var.app2_image}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http-app2" {
  #checkov:skip=CKV_AWS_2:Sin dominio ni certificado de ACM el listener es HTTP.
  #checkov:skip=CKV_AWS_103:No aplica a un listener HTTP; se cumple al agregar HTTPS con una política TLS 1.2.
  load_balancer_arn = aws_lb.this.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app2.arn
  }
}