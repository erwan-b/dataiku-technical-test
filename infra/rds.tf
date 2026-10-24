# The password is ephemeral and passed through write-only arguments: it reaches
# RDS and Secrets Manager but is never stored in the Terraform state.
ephemeral "random_password" "db" {
  length  = 32
  special = false # keeps DATABASE_URL free of characters that need URL-encoding
}

module "db_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name            = "${var.name}-db"
  use_name_prefix = false
  description     = "PostgreSQL access from the EKS cluster only"
  vpc_id          = module.vpc.vpc_id

  # Auto Mode nodes use the cluster primary security group, so pods reach RDS through it.
  ingress_rules = {
    postgresql_from_cluster = {
      from_port                    = 5432
      to_port                      = 5432
      referenced_security_group_id = module.eks.cluster_primary_security_group_id
    }
  }
}

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.2"

  identifier     = var.name
  engine         = "postgres"
  engine_version = "18" # major only: RDS picks the default minor
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = local.db_name
  username = local.db_username
  port     = 5432

  # The RDS-managed secret rotates every 7 days, which would break the static
  # Kubernetes Secret: the password is ours, sent write-only.
  manage_master_user_password = false
  password_wo                 = ephemeral.random_password.db.result
  password_wo_version         = local.db_password_version

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.db_security_group.id]
  publicly_accessible    = false
  multi_az               = false

  # Default parameter group; PostgreSQL has no option groups.
  create_db_parameter_group = false
  create_db_option_group    = false

  backup_retention_period  = 1
  delete_automated_backups = true

  # Demo settings: the whole stack must be destroyable in one command.
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true
}

module "database_url_secret" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "2.2.0"

  name = "${var.name}/database-url"
  # Immediate deletion, otherwise a destroy/apply cycle collides on the name.
  recovery_window_in_days = 0

  secret_string_wo         = "postgresql://${local.db_username}:${ephemeral.random_password.db.result}@${module.db.db_instance_endpoint}/${local.db_name}?sslmode=require"
  secret_string_wo_version = local.db_password_version
}
