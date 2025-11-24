variable "db_password" {
  description = "Master password for RDS"
  type        = string
  sensitive   = true
}
