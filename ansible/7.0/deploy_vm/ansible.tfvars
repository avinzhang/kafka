project = "avin"
aws_region = "ap-southeast-2"
cidr_block = "10.0.0.0/16"
subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
azs = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
name_security_groups = "avin-sg"
instance_count = 7
ec2_ami = "ami-08bd00d7713a39e7d"
ec2_type = "t2.medium"
public_key_path = "~/.ssh/id_rsa.pub"
private_key_path = "~/.ssh/id_rsa"
ingress_rules = [
  {
          from_port   = -1
          to_port     = -1
          protocol    = "icmp"
          cidr_block  = "0.0.0.0/0"
   },
  {
          from_port   = 22
          to_port     = 22
          protocol    = "tcp"
          cidr_block  = "0.0.0.0/0"
   },
   {
      from_port   = 2181
      to_port     = 2181
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 2182
      to_port     = 2182
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 2888
      to_port     = 2888
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 3888
      to_port     = 3888
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 8090
      to_port     = 8090
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 9091
      to_port     = 9091
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 9092
      to_port     = 9092
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 389
      to_port     = 389
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 636
      to_port     = 636
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 8081
      to_port     = 8081
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 8083
      to_port     = 8083
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 8088
      to_port     = 8088
      protocol    = "tcp"
      cidr_block  = "10.0.0.0/16"
   },
   {
      from_port   = 9021
      to_port     = 9021
      protocol    = "tcp"
      cidr_block  = "0.0.0.0/0"
   }
]

egress_rules = [
  {
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_block  = "0.0.0.0/0"
   }
]




