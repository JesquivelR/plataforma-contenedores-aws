variable "aws_region" {
  description = "Región de AWS para desplegar la infraestructura"
  type        = string
  default     = "us-west-1"
}

variable "github_owner" {
  description = "Usuario u organización de GitHub dueño del repositorio"
  type        = string
  default     = "JesquivelR"
}

variable "github_repo" {
  description = "Nombre del repositorio autorizado a asumir el rol"
  type        = string
  default     = "plataforma-contenedores-aws"
}

variable "github_branch" {
  description = "Rama autorizada a asumir el rol"
  type        = string
  default     = "main"
}

variable "github_environments" {
  description = "Entornos de GitHub autorizados a asumir el rol"
  type        = list(string)
  default     = ["dev", "stage"]
}

variable "role_name" {
  description = "Nombre del rol IAM para GitHub Actions"
  type        = string
  default     = "github-actions-plataforma-contenedores"
}

variable "role_policy_arns" {
  description = "ARNs de las políticas administradas que se adjuntan al rol"
  type        = list(string)
  default     = []
}
