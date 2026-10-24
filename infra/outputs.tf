output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecr_repository_name" {
  value = module.ecr.repository_name
}

output "database_url_secret_arn" {
  description = "Secrets Manager secret holding DATABASE_URL (read by scripts/deploy.sh)."
  value       = module.database_url_secret.secret_arn
}
