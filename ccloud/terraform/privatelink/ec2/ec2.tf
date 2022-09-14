terraform {
  required_version = ">= 0.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 4.25.0"
    }
  }
}

resource "aws_vpc" "default" {
  cidr_block = "${var.ec2_cidr}"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "avin-vpc-1"
  }
}

resource "aws_subnet" "subnet" {
  count = length(var.ec2_subnets)
  vpc_id                  = aws_vpc.default.id
  cidr_block              = element(concat(var.ec2_subnets, [""]), count.index)
  availability_zone       = element(concat(var.ec2_azs, [""]), count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "avin-ec2-subnet-${count.index}"
  }
}

locals {
  subnets = {
    for a in aws_subnet.subnet :
    a.availability_zone_id => a.id
  }
}

resource "aws_internet_gateway" "network-gw" {
  vpc_id = "${aws_vpc.default.id}"
  tags = {
    Name = "avin-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.default.id}"
  tags = {
    Name = "avin-rt"
  }
}

resource "aws_route" "public_igw_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.network-gw.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "public-rt" {
  count          = length(var.ec2_subnets)
  subnet_id = element(aws_subnet.subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2_security_groups" {
  name   = var.ec2_name_security_groups
  vpc_id = aws_vpc.default.id
}

resource "aws_security_group_rule" "ingress_rules" {
  count = length(var.ec2_ingress_rules)

  type              = "ingress"
  from_port         = var.ec2_ingress_rules[count.index].from_port
  to_port           = var.ec2_ingress_rules[count.index].to_port
  protocol          = var.ec2_ingress_rules[count.index].protocol
  cidr_blocks       = [var.ec2_ingress_rules[count.index].cidr_block]
  security_group_id = aws_security_group.ec2_security_groups.id
}

resource "aws_security_group_rule" "egress_rules" {
  count = length(var.ec2_egress_rules)

  type              = "egress"
  from_port         = var.ec2_egress_rules[count.index].from_port
  to_port           = var.ec2_egress_rules[count.index].to_port
  protocol          = var.ec2_egress_rules[count.index].protocol
  cidr_blocks       = [var.ec2_egress_rules[count.index].cidr_block]
  security_group_id = aws_security_group.ec2_security_groups.id
}

resource "aws_key_pair" "keypair" {
  key_name   = "avin-tf-sshkey"
  public_key = "${file(var.ec2_public_key_path)}"
}

resource "aws_instance" "instance" {
  count = var.ec2_instance_count
  ami = var.ec2_ami
  instance_type = var.ec2_type
  key_name = "${aws_key_pair.keypair.key_name}"
  associate_public_ip_address = true
  subnet_id = element(aws_subnet.subnet.*.id, count.index)
  vpc_security_group_ids      = [aws_security_group.ec2_security_groups.id]

  tags = {
    owner_email = var.owner_email
    Name = "avin-terraform-${count.index + 1}"
  }
}

