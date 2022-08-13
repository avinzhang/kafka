output "vpc-id" {
  value = "${aws_vpc.default.id}"
}

#output "subnet" {
#  value = {
#    for a in aws_subnet.subnet :
#    a.availability_zone_id => a.id
#  }
#}

output "cloudsub" {
  value = local.subnets
}

output "ec2-ip" {
  value = "${aws_instance.instance[0].public_ip}"
}

