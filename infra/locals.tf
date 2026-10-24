locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  db_name     = "filedrop"
  db_username = "filedrop"
  # Bump to rotate the password on the next apply.
  db_password_version = 1
}
