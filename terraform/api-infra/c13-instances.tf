# ============================================================
# c13-instances.tf
# EC2 Bastion Host (public subnet)
# Used for SSH tunneling to Valkey and private services.
# Decommissioned resources are preserved as comments.
# ============================================================

# ------------------------------------------------------------
# Ubuntu AMI — latest 20.04 LTS from Canonical
# ami and user_data changes are ignored to prevent unnecessary
# reboots when a newer AMI is published.
# ------------------------------------------------------------

data "aws_ami" "ubuntu-image" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# ------------------------------------------------------------
# Public Bastion Host
# Minimal t2.nano in a public subnet. Used for developer SSH
# tunnels to Valkey and other private resources.
# ------------------------------------------------------------

resource "aws_instance" "public-work-server" {
  ami           = data.aws_ami.ubuntu-image.id
  instance_type = "t2.nano"
  key_name      = "servefirst-keypair"
  user_data     = file("${path.module}/scripts/install-public.sh")
  subnet_id     = aws_subnet.public[0].id

  vpc_security_group_ids = [aws_security_group.allow-ssh.id]

  root_block_device {
    volume_size = "10"
    volume_type = "standard"
  }

  tags = {
    Name      = "${var.environment}-sfv2-public-bastion"
    Terraform = "true"
  }

  # Prevent re-creation when AMI receives a security patch update
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ------------------------------------------------------------
# [Decommissioned] MongoDB EC2 Instance
# Mongo has been migrated to Atlas; keeping for reference.
# ------------------------------------------------------------

# resource "aws_instance" "public-mongo" { ... }
# resource "aws_ebs_volume" "ebs" { ... }
# resource "aws_volume_attachment" "ebs" { ... }

# ------------------------------------------------------------
# [Decommissioned] Private Work Server
# No longer needed; ECS tasks replaced direct EC2 usage.
# ------------------------------------------------------------

# resource "aws_instance" "private-work-server" { ... }
