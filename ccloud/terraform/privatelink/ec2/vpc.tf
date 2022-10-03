resource "aws_vpc" "main" {
  cidr_block = "${var.ec2_cidr}"

  enable_dns_hostnames = true
  enable_dns_support = true
  instance_tenancy = "default"

  tags = {
    Name = "avin-tf-vpc"
  }

}

resource "aws_security_group" "ec2_security_groups" {
  name   = var.ec2_name_security_groups
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "avin-tf-sg"
  }
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

resource "aws_subnet" "sn_az" {
  count = length(local.availability_zones)

  availability_zone = local.availability_zones[count.index]

  vpc_id = aws_vpc.main.id
  map_public_ip_on_launch = false

  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 5, count.index+1)

  tags = {
    Name = "avin-tf-subnet${count.index + 1}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "avin-tf-gw"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "avin-tf-rt"
  }
}

resource "aws_route_table_association" "rt_assoc" {
  count = length(aws_subnet.sn_az)

  route_table_id = aws_route_table.rt.id
  subnet_id = aws_subnet.sn_az[count.index].id
}
