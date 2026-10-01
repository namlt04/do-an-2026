# network.tf
# Security Group cho ung dung web.
#
# MISCONFIG (baseline): mo cong quan tri/DB (22-SSH, 3306-MySQL) ra TOAN BO Internet
# (cidr_blocks = ["0.0.0.0/0"]). Day la be mat tan cong khong lo, de bi brute-force/khai thac.
#
# Huong sua: chi cho phep dai noi bo toi thieu can thiet (vi du 10.0.0.0/16),
# KHONG de cong quan tri/DB mo ra 0.0.0.0/0.

resource "aws_security_group" "web" {
  name        = "ptit-web-sg"
  description = "Security group cho web app"
  vpc_id      = aws_vpc.main.id

  # HTTPS phuc vu qua Load Balancer (ngoai pham vi bo ma nay) nen SG ung dung
  # KHONG mo 443 ra Internet o day. SG nay chi nen phuc vu quan tri noi bo.

  # MISCONFIG: SSH mo ra toan Internet
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MISCONFIG: MySQL mo ra toan Internet
  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress gioi han trong VPC (khong phai misconfig - de baseline on dinh)
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
