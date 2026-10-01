# variables.tf
# Bien cau hinh.
#
# MISCONFIG (baseline): SECRET HARDCODE trong default cua bien
#   (mat khau DB va secret key ghi cung ngay trong ma -> lo trong Git history).
#
# Huong sua:
#   - Xoa cac gia tri bi mat khoi default.
#   - Danh dau bien nhay cam bang sensitive = true; truyen gia tri luc chay
#     (TF_VAR_... hoac *.tfvars khong commit).

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "app_bucket_name" {
  type    = string
  default = "ptit-devsecops-app-data"
}

# MISCONFIG: mat khau DB ghi cung
variable "db_password" {
  type    = string
  default = "P@ssw0rd_SuperSecret_2024!"
}

# MISCONFIG: AWS secret access key ghi cung (gia lap)
variable "aws_secret_key" {
  type    = string
  default = "wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY"
}
