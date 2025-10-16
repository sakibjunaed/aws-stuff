
# This is required for everything
provider "aws" {
  region = "us-east-1"
}

# Data blocks define data to be referenced
# The aws_vpc part says the data is about the vpc resource and the default is the name of the data piece
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Make a security group for the EFS
# Security groups belong to a VPC so link it using a VPC ID
# ingress defines inbound traffic rule and egress outbound
# protocol -1 means all protocols

resource "aws_security_group" "efs_sg" {
  name        = "efs-sg"
  description = "Allow NFS traffic for EFS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# create the EFS file share
# define performance_mode

resource "aws_efs_file_system" "efs" {
  creation_token   = "efs-default"
  performance_mode = "generalPurpose"
}

# create a mount target in the subnet in the default vpc
# define the filesystem it connects to
# define the subnet its in
# define the security group for the mount target

resource "aws_efs_mount_target" "efs_mount" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = data.aws_subnets.default.ids[0] # pick the first subnet
  security_groups = [aws_security_group.efs_sg.id]
}

# Security group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow outbound traffic to EFS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instances
resource "aws_instance" "ec2_instances" {
  count           = 2
  ami             = "ami-0c02fb55956c7d316" # Amazon Linux 2 in us-east-1
  instance_type   = "t2.micro"
  subnet_id       = data.aws_subnets.default.ids[0]
  security_groups = [aws_security_group.ec2_sg.id]

  # Mount EFS at launch
  user_data = <<-EOF
              #!/bin/bash
              yum install -y amazon-efs-utils
              mkdir -p /mnt/efs
              mount -t efs ${aws_efs_file_system.efs.id}:/ /mnt/efs
              EOF

  tags = {
    Name = "EC2-Instance-${count.index + 1}"
  }
}
