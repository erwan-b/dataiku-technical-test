variable "name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "filedrop"
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-3"
}

variable "vpc_cidr" {
  description = "CIDR of the VPC. Subnets are carved out of it."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS API endpoint. Restrict to your IP for anything beyond a demo."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
