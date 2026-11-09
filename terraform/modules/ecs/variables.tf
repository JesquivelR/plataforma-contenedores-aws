variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "aws_region" {
  description = "Región de AWS"
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

variable "subnets" {
  description = "Subredes para ECS"
  type        = list(string)
}

variable "security_group_id" {
  description = "ID del grupo de seguridad"
  type        = string
}

variable "app1_target_group_arn" {
  description = "ARN del target group para App1"
  type        = string
}

variable "app2_target_group_arn" {
  description = "ARN del target group para App2"
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

variable "desired_count" {
  description = "Número deseado de tareas"
  type        = number
  default     = 2
}
