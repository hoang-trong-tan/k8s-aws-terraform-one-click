variable "subnet_id_for_ec2" {}
variable "sg_id_for_ec2" {}
variable "tags_ec2" {
  type = map(string)
}
variable "key_name" {
  type = string
}