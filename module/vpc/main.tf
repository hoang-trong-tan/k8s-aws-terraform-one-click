resource "aws_vpc" "demo" {
    cidr_block = var.cidr_vpc

    tags = var.tags_vpc
}

resource "aws_subnet" "demo" {
    for_each = var.cidr_subnet
    vpc_id = aws_vpc.demo.id
   
    cidr_block = each.value.cidr_block
    availability_zone = each.value.az
    map_public_ip_on_launch = each.value.tier == "public" ? true : false

    tags = merge(var.tag_subnet,{
      Name = each.key
      tier = each.value.tier
    })

}

resource "aws_internet_gateway" "demo" {
    vpc_id = aws_vpc.demo.id
    tags = var.tags_igw
}

resource "aws_route_table" "demoPublic" {
    vpc_id = aws_vpc.demo.id
    tags = var.tags_rt
}

resource "aws_route" "routePublic" {
    route_table_id = aws_route_table.demoPublic.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  
}

resource "aws_route_table_association" "demoPublic" {
    for_each = {
        for k, v in aws_subnet.demo : k => v if v.tags["tier"] == "public"
    }
    subnet_id = each.value.id
    route_table_id = aws_route_table.demoPublic.id
}

resource "aws_security_group" "demo_sg_alb" {
    name = var.name_sg_alb
    description = "Security group for ALB"
    vpc_id = aws_vpc.demo.id
  
}

resource "aws_security_group_rule" "ingress_alb" {
    type = "ingress"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = aws_security_group.demo_sg_alb.id
}


resource "aws_security_group_rule" "ingress_alb1" {
    type = "ingress"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = aws_security_group.demo_sg_alb.id
}


resource "aws_security_group_rule" "egress_alb" {
  type = "egress"
  to_port = 0
  from_port = 0
  protocol = "-1"
  security_group_id = aws_security_group.demo_sg_alb.id
  cidr_blocks = ["0.0.0.0/0"]
}




resource "aws_security_group" "demo_sg_ec2" {
    name = var.name_sg_ec2
    description = "Security group for ec2"
    vpc_id = aws_vpc.demo.id
  
}

resource "aws_security_group_rule" "ingress_ec2" {
    type = "ingress"
    from_port = 8443
    to_port = 8443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = aws_security_group.demo_sg_ec2.id
}

resource "aws_security_group_rule" "ingress_ec2_1" {
    type = "ingress"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_group_id = aws_security_group.demo_sg_ec2.id
}

resource "aws_security_group_rule" "ingress_ec2_2" {
    type = "ingress"
    from_port = 30000
    to_port = 30000
    protocol = "tcp"
    source_security_group_id = aws_security_group.demo_sg_alb.id
    security_group_id = aws_security_group.demo_sg_ec2.id
}


resource "aws_security_group_rule" "egress_ec2" {
  type = "egress"
  to_port = 0
  from_port = 0
  protocol = "-1"
  security_group_id = aws_security_group.demo_sg_ec2.id
  cidr_blocks = ["0.0.0.0/0"]
}