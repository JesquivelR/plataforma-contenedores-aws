# Proveedor OIDC de GitHub y rol que asumen los workflows de este repositorio
# sin llaves estáticas de AWS.

locals {
  github_repo = "${var.github_owner}/${var.github_repo}"

  # Solo la rama principal y los entornos declarados pueden asumir el rol.
  oidc_subjects = concat(
    ["repo:${local.github_repo}:ref:refs/heads/${var.github_branch}"],
    [for env in var.github_environments : "repo:${local.github_repo}:environment:${env}"]
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.oidc_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

# Ajustar a los permisos que necesite el despliegue (ECR, ECS, VPC, ALB, IAM, Lambda y estado en S3).
resource "aws_iam_role_policy_attachment" "github_actions" {
  for_each   = toset(var.role_policy_arns)
  role       = aws_iam_role.github_actions.name
  policy_arn = each.value
}
