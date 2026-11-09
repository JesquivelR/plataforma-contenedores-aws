variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "aws_region" {
  description = "Región de AWS"
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

variable "services_json" {
  description = "Servicios a actualizar con sus imágenes Docker"
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

