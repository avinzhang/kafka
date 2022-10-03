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
  subnet_id = element(aws_subnet.sn_az.*.id, count.index)
  vpc_security_group_ids      = [aws_security_group.ec2_security_groups.id]

  tags = {
    owner_email = var.owner_email
    Name = "avin-terraform-${count.index + 1}"
  }
}
