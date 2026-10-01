# iam.tf
# IAM role/policy cap quyen cho EC2 truy cap S3.
#
# MISCONFIG (baseline): policy dung Action = "*" tren Resource = "*"
#   -> vi pham least-privilege; mot credential bi lo co the chiem toan bo tai khoan cloud.
#
# Huong sua: gioi han hanh dong va tai nguyen toi thieu can thiet, vi du chi cho phep
#   doc/ghi dung bucket cua ung dung:
#     Action   = ["s3:GetObject", "s3:PutObject"]
#     Resource = ["arn:aws:s3:::<bucket>/*"]

resource "aws_iam_role" "app" {
  name = "ptit-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "app" {
  name = "ptit-app-policy"
  role = aws_iam_role.app.id

  # MISCONFIG: quyen qua rong
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}
