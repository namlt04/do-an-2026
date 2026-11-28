resource "aws_instance" "web" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app.id

  vpc_security_group_ids = [aws_security_group.web.id]

  root_block_device {
    volume_size = 20
    encrypted = false
  }

  tags = {
    Name = "ptit-web-instance"
  }
}
