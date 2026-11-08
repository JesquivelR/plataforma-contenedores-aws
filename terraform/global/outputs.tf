output "github_actions_role_arn" {
  description = "ARN del rol para usar en role-to-assume de los workflows"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN del proveedor OIDC de GitHub"
  value       = aws_iam_openid_connect_provider.github.arn
}
