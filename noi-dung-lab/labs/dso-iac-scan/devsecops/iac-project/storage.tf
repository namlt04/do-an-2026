# storage.tf
# S3 bucket luu du lieu ung dung.
#
# MISCONFIG (baseline):
#   - public_access_block TAT ca 4 co (cho phep public) -> lo lot du lieu.
#   - THIEU ma hoa at-rest (server-side encryption).
#   - THIEU versioning.
#   - THIEU access logging.
#
# Huong sua:
#   - Dat ca 4 co cua aws_s3_bucket_public_access_block = true.
#   - Them aws_s3_bucket_server_side_encryption_configuration (bat ma hoa).
#   - Them aws_s3_bucket_versioning (Enabled).
#   - (Task 4) Them aws_s3_bucket_logging tro toi bucket log da hardening.

resource "aws_s3_bucket" "data" {
  bucket = "ptit-devsecops-app-data"

  tags = {
    Name = "app-data"
  }
}

# MISCONFIG: cho phep public access (dang le phai chan tat ca)
resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# MISCONFIG: KHONG co server_side_encryption_configuration -> khong ma hoa at-rest
# MISCONFIG: KHONG co aws_s3_bucket_versioning -> mat kha nang khoi phuc
# MISCONFIG: KHONG co aws_s3_bucket_logging  -> khong co access log
