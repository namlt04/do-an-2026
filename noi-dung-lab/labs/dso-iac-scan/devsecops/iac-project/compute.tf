# compute.tf
# EC2 instance chay ung dung web.
#
# MISCONFIG (baseline):
#   - Khong ep IMDSv2 (metadata_options thieu) -> nguy co SSRF doc credential tu IMDS.
#   - root_block_device khong ma hoa (encrypted = false) -> du lieu tren disk khong ma hoa.
#
# Huong sua:
#   - Them metadata_options { http_tokens = "required" } (ep IMDSv2).
#   - root_block_device { encrypted = true }.

resource "aws_instance" "web" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app.id

  vpc_security_group_ids = [aws_security_group.web.id]

  # MISCONFIG: khong co metadata_options -> IMDSv1 van duoc chap nhan

  root_block_device {
    volume_size = 20
    # MISCONFIG: khong ma hoa EBS
    encrypted = false
  }

  tags = {
    Name = "ptit-web-instance"
  }
}
