variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "ecs_cluster" {
  description = "ID del clúster ECS"
  type        = string
}

variable "repositorio_ecr" {
  description = "Repositorio ECR"
  type        = string
}

variable "app1_image" {
  description = "Imagen Docker para App1"
  type        = string
}

variable "app2_image" {
  description = "Imagen Docker para App2"
  type        = string
}

variable "image_tag" {
  description = "Tag de imagen docker"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN del rol de ejecución de ECS"
  type        = string
}

variable "task_role_arn" {
  description = "ARN del rol de tarea de ECS"
  type        = string
}
