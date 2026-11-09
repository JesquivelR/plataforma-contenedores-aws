variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  default     = "stage"
}

variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "us-west-1"
}

variable "repositorio_ecr" {
  description = "Repositorio ECR"
  type        = string
}

variable "app1_image" {
  description = "Imagen Docker para App1"
  type        = string
  default     = "app1"
}

variable "app2_image" {
  description = "Imagen Docker para App2"
  type        = string
  default     = "app2"
}

variable "image_tag" {
  description = "Tag de imagen docker"
  type        = string
  default     = "latest"
}

variable "vpc_cidr" {
  description = "CIDR para la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  type        = list(string)
  description = "Subnets publicas"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type        = list(string)
  description = "Subnets privadas"
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Zonas de disponibilidad"
  default     = ["us-west-1a", "us-west-1b"]
}