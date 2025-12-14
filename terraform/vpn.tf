# Latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Key pair for VPN server access
resource "aws_key_pair" "vpn" {
  key_name   = "${local.project_name}-vpn-key"
  public_key = file("${path.module}/vpn_server_key.pub")

  tags = local.common_tags
}

# Elastic IP for VPN server
resource "aws_eip" "vpn" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpn-eip"
  })
}

# VPN Server EC2 instance
resource "aws_instance" "vpn" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.vpn.key_name
  subnet_id     = aws_subnet.public[0].id

  vpc_security_group_ids = [aws_security_group.vpn_server.id]

  # Enable IP forwarding
  source_dest_check = false

  user_data = templatefile("${path.module}/user_data/wireguard.sh", {
    vpn_client_cidr     = var.vpn_client_cidr
    vpc_cidr            = var.vpc_cidr
    private_api_dns     = "private-api.seasats.local"
    vpn_server_port     = var.vpn_server_port
  })

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpn-server"
  })
}

# Associate Elastic IP with VPN server
resource "aws_eip_association" "vpn" {
  instance_id   = aws_instance.vpn.id
  allocation_id = aws_eip.vpn.id
}
