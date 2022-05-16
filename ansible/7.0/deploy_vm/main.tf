terraform {
  backend "local" {
    path = "/tmp/terraform.tfstate"
  }
}

provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_vpc" "default" {
  cidr_block = "${var.cidr_block}"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "${var.project}-vpc"
  }
}

resource "aws_subnet" "subnet" {
  count = length(var.subnets)

  vpc_id                  = aws_vpc.default.id
  cidr_block              = element(concat(var.subnets, [""]), count.index)
  availability_zone       = element(concat(var.azs, [""]), count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project}-public-${count.index}"
  }
}

resource "aws_internet_gateway" "network-gw" {
  vpc_id = "${aws_vpc.default.id}"
  tags = {
    Name = "${var.project}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.default.id}"
  tags = {
    Name = "${var.project}-rt"
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
  count          = length(var.subnets)
  subnet_id = element(aws_subnet.subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}


resource "aws_security_group" "ec2_security_groups" {
  name   = var.name_security_groups
  vpc_id = aws_vpc.default.id
}

resource "aws_security_group_rule" "ingress_rules" {
  count = length(var.ingress_rules)

  type              = "ingress"
  from_port         = var.ingress_rules[count.index].from_port
  to_port           = var.ingress_rules[count.index].to_port
  protocol          = var.ingress_rules[count.index].protocol
  cidr_blocks       = [var.ingress_rules[count.index].cidr_block]
  security_group_id = aws_security_group.ec2_security_groups.id
}

resource "aws_security_group_rule" "egress_rules" {
  count = length(var.egress_rules)

  type              = "egress"
  from_port         = var.egress_rules[count.index].from_port
  to_port           = var.egress_rules[count.index].to_port
  protocol          = var.egress_rules[count.index].protocol
  cidr_blocks       = [var.egress_rules[count.index].cidr_block]
  security_group_id = aws_security_group.ec2_security_groups.id
}

resource "aws_key_pair" "keypair" {
  key_name   = "cluster"
  public_key = "${file(var.public_key_path)}"
}

resource "aws_instance" "instance" {
  count = var.instance_count
  ami = var.ec2_ami
  instance_type = var.ec2_type
  key_name = "${aws_key_pair.keypair.key_name}"
  associate_public_ip_address = true
  subnet_id = element(aws_subnet.subnet.*.id, count.index)
  vpc_security_group_ids      = [aws_security_group.ec2_security_groups.id]

  tags = {
    Owner = var.project
    Name = "${var.project}-terraform-${count.index + 1}"
  }
}

