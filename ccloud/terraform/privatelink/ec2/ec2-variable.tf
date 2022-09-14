###EC2 side
variable "aws_region" {
  type = string
  description = "AWS region to be used"
  default = "ap-southeast-2"
}

variable "ec2_cidr" {
  type = string
  description = "EC2 vpc cidr block"
  default = "10.11.0.0/16"
}

variable "ec2_subnets" {
  type = list(string)
  description = "EC2 vpc subnet"
  default = ["10.11.1.0/24", "10.11.2.0/24", "10.11.3.0/24"]
}


variable "ec2_azs" {
  type = list(string)
  description = "EC2 AZ"
  default = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
}


variable "ec2_name_security_groups" {
  type = string
  description = "EC2 security group"
  default = "avin-tf-sg"
}


variable "ec2_ingress_rules" {
  type = list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_block  = string
    }))
  description = "EC2 ingress rules"
  default = [ 
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
          from_port   = 443
          to_port     = 443
          protocol    = "tcp" 
          cidr_block  = "0.0.0.0/0" 
   }, 
  { 
          from_port   = 9092
          to_port     = 9092
          protocol    = "tcp" 
          cidr_block  = "0.0.0.0/0" 
   } 

   ] 
}


variable "ec2_egress_rules" {
  type = list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_block  = string
    }))
  description = "EC2 ingress rules"
  default = [
  {
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_block  = "0.0.0.0/0"
   }
  ]
}

variable "ec2_public_key_path" {
  type = string
  default = "~/.ssh/id_rsa.pub"
}


variable "ec2_instance_count" {
  type = number
  default = 1
}

variable "ec2_ami" {
  description = "ami used"
  type = string
  default = "ami-08bd00d7713a39e7d"
}

variable "ec2_type" {
  description = "Image type used"
  type = string
  default = "t2.medium"
}

variable "owner_email" {
  type = string
}




