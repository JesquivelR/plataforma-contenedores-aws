output "alb_dns" {
  description = "DNS del ALB"
  value       = module.alb.alb_dns
  sensitive   = false
}