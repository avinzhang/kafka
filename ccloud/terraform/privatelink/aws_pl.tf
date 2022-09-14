variable "vpc_id" {
  description = "The VPC ID to private link to Confluent Cloud"
  type = string
}

#variable "privatelink_service_name" {
#  description = "The Service Name from Confluent Cloud to Private Link with (provided by Confluent)"
#  type = string
#}
#
#variable "bootstrap" {
#  description = "The bootstrap server (ie: lkc-abcde-vwxyz.us-east-1.aws.glb.confluent.cloud:9092)"
#  type = string
#}
#
variable "subnets_to_privatelink" {
  description = "A map of Zone ID to Subnet ID (ie: {\"use1-az1\" = \"subnet-abcdef0123456789a\", ...})"
  type = map(string)
}


locals {
  hosted_zone = replace(regex("^[^.]+-([0-9a-zA-Z]+[.].*):[0-9]+$", confluent_kafka_cluster.dedicated.bootstrap_endpoint)[0], "glb.", "")
}

provider "aws" {
  region = var.aws_region
}


data "aws_vpc" "privatelink" {
  id = var.vpc_id
}

data "aws_availability_zone" "privatelink" {
  for_each = var.subnets_to_privatelink
  zone_id = each.key
}

locals {
  bootstrap = split(":", confluent_kafka_cluster.dedicated.bootstrap_endpoint)[0]
}

locals {
  bootstrap_prefix = split(".", confluent_kafka_cluster.dedicated.bootstrap_endpoint)[0]
}


resource "aws_security_group" "privatelink" {
  # Ensure that SG is unique, so that this module can be used multiple times within a single VPC
  name = "ccloud-privatelink_${local.bootstrap_prefix}_${var.vpc_id}"
  description = "Confluent Cloud Private Link minimal security group for ${confluent_kafka_cluster.dedicated.bootstrap_endpoint} in ${var.vpc_id}"
  vpc_id = data.aws_vpc.privatelink.id

  ingress {
    # only necessary if redirect support from http/https is desired
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [data.aws_vpc.privatelink.cidr_block]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [data.aws_vpc.privatelink.cidr_block]
  }

  ingress {
    from_port = 9092
    to_port = 9092
    protocol = "tcp"
    cidr_blocks = [data.aws_vpc.privatelink.cidr_block]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "privatelink" {
  vpc_id = data.aws_vpc.privatelink.id
  service_name = confluent_network.private-link.aws[0].private_link_endpoint_service
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.privatelink.id,
  ]

  subnet_ids = [for zone, subnet_id in var.subnets_to_privatelink: subnet_id]
  private_dns_enabled = false

  depends_on = [
    confluent_private_link_access.aws,
  ]

}

resource "aws_route53_zone" "privatelink" {
  name = local.hosted_zone

  vpc {
    vpc_id = data.aws_vpc.privatelink.id
  }
}

resource "aws_route53_record" "privatelink" {
  count = length(var.subnets_to_privatelink) == 1 ? 0 : 1
  zone_id = aws_route53_zone.privatelink.zone_id
  name = "*.${aws_route53_zone.privatelink.name}"
  type = "CNAME"
  ttl  = "60"
  records = [
    aws_vpc_endpoint.privatelink.dns_entry[0]["dns_name"]
  ]
}

locals {
  endpoint_prefix = split(".", aws_vpc_endpoint.privatelink.dns_entry[0]["dns_name"])[0]
}

resource "aws_route53_record" "privatelink-zonal" {
  for_each = var.subnets_to_privatelink

  zone_id = aws_route53_zone.privatelink.zone_id
  name = length(var.subnets_to_privatelink) == 1 ? "*" : "*.${each.key}"
  type = "CNAME"
  ttl  = "60"
  records = [
    format("%s-%s%s",
      local.endpoint_prefix,
      data.aws_availability_zone.privatelink[each.key].name,
      replace(aws_vpc_endpoint.privatelink.dns_entry[0]["dns_name"], local.endpoint_prefix, "")
    )
  ]
}


# Setup proxy
variable "ec2_ip" {
  type = string
}

resource "null_resource" "remote"{
  connection {
       type = "ssh"
       user = "centos"
       private_key = file("~/.ssh/id_rsa")
       host  = var.ec2_ip
  }

#  triggers = {
#    timestamp = timestamp()
#  }

  provisioner "file" {
    source      = "./nginx.sh"
    destination = "/tmp/nginx.sh"
  }
  provisioner "remote-exec" {
         inline = [
                       "sudo yum install epel-release -y",
                       "sudo yum install nginx nginx-mod-stream -y",
                       "sudo chmod +x /tmp/nginx.sh",
                       "sudo /tmp/nginx.sh",
                       "sudo cp /tmp/nginx.conf /etc/nginx/nginx.conf",
                       "sudo semanage port -a -t http_port_t  -p tcp 9092",
                       "sudo systemctl start nginx"
                  ]
  }
}
