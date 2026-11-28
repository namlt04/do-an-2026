variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "app_bucket_name" {
  type    = string
  default = "ptit-devops-app-data"
}

variable "db_password" {
  type    = string
  default = "P@ssw0rd_SuperSecret_2024!"
}

variable "aws_secret_key" {
  type    = string
  default = "wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY"
}
