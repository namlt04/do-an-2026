#!/bin/bash
#
# solver.sh -- LOI GIAI MAU cho bai dso-iac-scan. KHONG phat cho sinh vien.
#
# Muc dich: chay TRONG container `devsecops` (sau khi `labtainer dso-iac-scan`
# / `rebuild dso-iac-scan` da khoi dong lab) de tu dong thuc hien TRON CHUOI
# tu baseline scan -> remediation -> vuot quality gate -> lay flag. Dung de
# TU KIEM TRA rang toan bo goal (baseline_scan, fix_network_storage,
# fix_secret_iam, pass_gate) co the dat PASS khi bai duoc giai dung, truoc
# khi giao cho sinh vien.
#
# Cach chay (tu may build/test, VD sau khi rebuild lab va container dang
# chay):
#   docker exec -it <ten_container_devsecops> bash -c 'bash ~/solver.sh'
# hoac dan noi dung file nay vao 1 terminal cua lab (copy/paste), hoac copy
# file vao ~/solver.sh trong container roi chay `bash ~/solver.sh`.
#
# Sau khi chay xong: dung `checkwork`/gradelab de xac nhan goals PASS.
#
set -u

PROJ="$HOME/iac-project"
cd "$PROJ" || { echo "[solver] Khong tim thay $PROJ"; exit 1; }

HISTFILE_TARGET="$HOME/.bash_history"

echo "=== [1/6] terraform init/validate + quet baseline (Nhiem vu 1) ==="
terraform init -backend=false >/dev/null 2>&1
terraform validate
tfsec . || true
tfsec . --format json --out "$HOME/baseline.json"
echo "Baseline severity count:"
grep -o '"severity":"[A-Z]*"' "$HOME/baseline.json" | sort | uniq -c

{
    echo "cd ~/iac-project"
    echo "terraform init -backend=false"
    echo "terraform validate"
    echo "tfsec ."
    echo "tfsec . --format json --out ~/baseline.json"
    echo "grep -o '\"severity\":\"[A-Z]*\"' ~/baseline.json | sort | uniq -c"
    echo "checkov -d . --compact -o cli"
    echo "trivy config --severity HIGH,CRITICAL ."
} >> "$HISTFILE_TARGET"

echo
echo "=== [2/6] Sua network.tf (Nhiem vu 2 - siet Security Group) ==="
cat > network.tf <<'EOF'
# network.tf
# Security Group cho ung dung web.
# DA KHAC PHUC: khong con ingress nao mo ra 0.0.0.0/0 tren cong quan tri/DB.
# Chi cho phep dai quan tri noi bo (10.0.0.0/16) truy cap SSH/MySQL.

resource "aws_security_group" "web" {
  name        = "ptit-web-sg"
  description = "Security group cho web app"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH - chi tu dai quan tri noi bo"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    description = "MySQL - chi tu dai quan tri noi bo"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Egress trong VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = {
    Name = "ptit-web-sg"
  }
}
EOF

echo "=== [3/6] Sua storage.tf + logging.tf (Nhiem vu 2 + 4 - S3, logging) ==="
cat > storage.tf <<'EOF'
# storage.tf
# S3 bucket luu du lieu ung dung.
# DA KHAC PHUC: chan public access, bat ma hoa at-rest, bat versioning,
# bat access logging (tro toi bucket log trong logging.tf).

resource "aws_s3_bucket" "data" {
  bucket = "ptit-devsecops-app-data"

  tags = {
    Name = "app-data"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "data" {
  bucket        = aws_s3_bucket.data.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "log/app-data/"
}
EOF

cat > logging.tf <<'EOF'
# logging.tf
# DA KHAC PHUC (Nhiem vu 4): bat VPC flow log va S3 access log.

# Bucket rieng de chua access log cua bucket du lieu (cung duoc hardening).
resource "aws_s3_bucket" "logs" {
  bucket = "ptit-devsecops-app-logs"

  tags = {
    Name = "app-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# VPC Flow Log -> CloudWatch Logs
resource "aws_cloudwatch_log_group" "vpc" {
  name              = "/ptit/vpc/flowlogs"
  retention_in_days = 30
}

resource "aws_iam_role" "flowlog" {
  name = "ptit-vpc-flowlog-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flowlog" {
  name = "ptit-vpc-flowlog-policy"
  role = aws_iam_role.flowlog.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  log_destination = aws_cloudwatch_log_group.vpc.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
  iam_role_arn    = aws_iam_role.flowlog.arn
}
EOF

echo
echo "=== [4/6] Sua variables.tf + iam.tf (Nhiem vu 3 - secret + IAM) ==="
cat > variables.tf <<'EOF'
# variables.tf
# DA KHAC PHUC (Nhiem vu 3): loai bo secret hardcode khoi default; danh dau
# bien nhay cam bang sensitive = true. Gia tri that duoc truyen luc chay qua
# TF_VAR_db_password / TF_VAR_aws_secret_key hoac file *.tfvars khong commit.

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "app_bucket_name" {
  type    = string
  default = "ptit-devsecops-app-data"
}

variable "db_password" {
  type      = string
  sensitive = true
  # KHONG dat default la mat khau that.
}

variable "aws_secret_key" {
  type      = string
  sensitive = true
  # KHONG dat default la secret key that.
}
EOF

cat > iam.tf <<'EOF'
# iam.tf
# DA KHAC PHUC (Nhiem vu 3): policy ap dung least-privilege, chi cho phep
# doc/ghi dung bucket du lieu cua ung dung thay vi Action:*/Resource:*.

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

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = ["arn:aws:s3:::${var.app_bucket_name}/*"]
      }
    ]
  })
}
EOF

echo
echo "=== [5/6] Sua compute.tf (loi phu: IMDSv2 + ma hoa EBS) ==="
cat > compute.tf <<'EOF'
# compute.tf
# EC2 instance chay ung dung web.
# DA KHAC PHUC: ep IMDSv2 (http_tokens = required) va bat ma hoa EBS.

resource "aws_instance" "web" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app.id

  vpc_security_group_ids = [aws_security_group.web.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "ptit-web-instance"
  }
}
EOF

echo
echo "=== [6/6] Quet lai, git diff, vuot gate va lay flag (Nhiem vu 4) ==="
terraform validate
tfsec . --format json --out "$HOME/after.json"
echo "After severity count:"
grep -o '"severity":"[A-Z]*"' "$HOME/after.json" | sort | uniq -c

echo
echo "--- git diff --stat (bang chung remediation) ---"
git diff --stat 2>/dev/null

{
    echo "git diff network.tf storage.tf"
    echo "grep -rniE \"password|secret|access_key\" ~/iac-project"
    echo "git diff variables.tf iam.tf"
    echo "tfsec . --format json --out ~/after.json"
    echo "grep -o '\"severity\":\"[A-Z]*\"' ~/after.json | sort | uniq -c"
    echo "~/gate.sh"
} >> "$HISTFILE_TARGET"

echo
echo ">>> Goi CI quality gate (~/gate.sh) ..."
bash "$HOME/gate.sh"

echo
if [ -s "$HOME/flag.txt" ]; then
    echo "[solver] THANH CONG - flag da luu tai ~/flag.txt:"
    cat "$HOME/flag.txt"
    exit 0
else
    echo "[solver] CHUA lay duoc flag - xem output ~/gate.sh o tren de biet ly do."
    exit 1
fi
