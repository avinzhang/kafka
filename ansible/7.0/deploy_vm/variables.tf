variable "project" {
  description = "Project name"
  type = string
}

variable "aws_region" {
  description = "AWS Deployment region.."
  type = string
}


variable "cidr_block" {
  type = string
}

variable "subnets" {
  description = "List of public subnets for the VPC"
  type        = list(string)
}

variable "azs" {
  description = "List of availability zones names in the region"
  type        = list(string)
}

variable "name_security_groups" {
  description = "Name of Security Group"
  type = string
}

variable "ingress_rules" {
  description = "Ingress Rules"
  type = list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_block  = string
    }))
}

variable "egress_rules" {
  description = "Egress Rules"
  type = list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_block  = string
    }))
}

variable "instance_count" {
  description = "The number of instances to be created"
  type = number
}


variable "ec2_ami" {
  description = "ami used"
  type = string
}

variable "ec2_type" {
  description = "Image type used"
  type = string
}

variable "public_key_path" {
  description = "The local public key path, e.g. ~/.ssh/id_rsa.pub"
  type = string
}

variable "private_key_path" {
  description = "The local public key path, e.g. ~/.ssh/id_rsa"
  type = string
}
