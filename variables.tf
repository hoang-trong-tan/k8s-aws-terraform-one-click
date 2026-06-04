variable "cidr_vpc" {
  type = string
}

variable "cidr_subnet" {
  type = map(object({
    cidr_block = string
    tier       = string
    az         = string
  }))
}

variable "tags_vpc" {
  type = map(string)
}

variable "tag_subnet" {
  type = map(string)
}


variable "tags_igw" {
  type = map(string)
}

variable "tags_rt" {
  type = map(string)
}

variable "name_sg_alb" {
  type = string

}

variable "name_sg_ec2" {
  type = string

}
variable "tags_ec2" {
  type = map(string)
}

