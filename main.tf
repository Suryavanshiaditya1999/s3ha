provider "aws" {
  region = "us-west-1"
}

resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "vpc-s3ha"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "s3ha-igw"
  }
}

# public subnet

resource "aws_subnet" "public1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "public1"
  }
  availability_zone = "us-west-1b"
}

resource "aws_subnet" "public2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "public2"
  }
  availability_zone = "us-west-1c"
}

# public route table

resource "aws_route_table" "s3ha_rt_public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "s3ha-rt-public"
  }
}

resource "aws_route_table_association" "association1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.s3ha_rt_public.id
}

resource "aws_route_table_association" "association2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.s3ha_rt_public.id
}

# elatic ip

resource "aws_eip" "deploy_elasticip" {
  domain = "vpc"
  tags = {
    Name = "s3ha-elastic-ip"
  }
}


# nat gateway

resource "aws_nat_gateway" "deploy_nat_gateway" {
  allocation_id = aws_eip.deploy_elasticip.allocation_id
  subnet_id     = aws_subnet.public1.id

  tags = {
    Name = "s3ha-nat-gateway"
  }

}

# private subnet

resource "aws_subnet" "private1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  map_public_ip_on_launch = false
  tags = {
    Name = "private1"
  }
}

resource "aws_subnet" "private2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.4.0/24"
  map_public_ip_on_launch = false
  tags = {
    Name = "private2"
  }
}

# private route table

resource "aws_route_table" "s3ha_rt_private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.deploy_nat_gateway.id
  }
  tags = {
    Name = "s3ha-rt-private"
  }
}

resource "aws_route_table_association" "association3" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.s3ha_rt_private.id
}

resource "aws_route_table_association" "association4" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.s3ha_rt_private.id
}

# public instance 

resource "aws_security_group" "jump_security_group" {
  name        = "public-sg"
  description = "sg for jump server"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name = "public-sg"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_network_interface" "public_network_interface" {
  subnet_id = aws_subnet.public1.id
  security_groups = [aws_security_group.jump_security_group.id]
  tags = {
    Name = "public-network-interface"
  }
}

resource "aws_instance" "public" {
  ami           = "ami-08012c0a9ee8e21c4" # us-west-1
  instance_type = "t2.micro"
  key_name = "one"

  network_interface {
    network_interface_id = aws_network_interface.public_network_interface.id
    device_index         = 0
  }

  tags = {
    Name = "public-instance"
  } 
}

# Application layer instance

resource "aws_security_group" "application_security_group" {
  name        = "application-sg"
  description = "sg for application"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name = "application-sg"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
    ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_network_interface" "application_network_interface" {
  subnet_id = aws_subnet.private1.id
  security_groups = [aws_security_group.application_security_group.id]
  tags = {
    Name = "application-network-interface"
  }
}

resource "aws_instance" "application" {
  ami           = "ami-08012c0a9ee8e21c4" # us-west-1
  instance_type = "t2.micro"
  key_name = "one"

  network_interface {
    network_interface_id = aws_network_interface.application_network_interface.id
    device_index         = 0
    
  }

  tags = {
    Name = "application-instance"
  } 
}


# Launch Template

resource "aws_launch_template" "s3ha_launch_template" {
  name = "application-template"

  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size = 20
      volume_type = "gp3"
    }
  }

  network_interfaces {
    subnet_id                   = aws_subnet.private1.id
    associate_public_ip_address = false
    security_groups             = [aws_security_group.application_security_group.id]
  }

  key_name      = "one"
  image_id      = "ami-08012c0a9ee8e21c4"
  instance_type = "t2.micro"

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "application"
    }
  }
}


# load balancer

resource "aws_lb" "test" {
  name               = "s3ha-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.application_security_group.id]
  subnets            = [aws_subnet.public1.id , aws_subnet.public2.id]
}

resource "aws_lb_target_group" "deploy_tg" {
  name     = "s3ha-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   =  aws_vpc.main.id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.test.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.deploy_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.deploy_tg.arn
  target_id        = aws_instance.application.id
  port             = 80
}


# auto scaling

resource "aws_autoscaling_group" "bar" {
  name                      = "s3ha-aut-scale"
  max_size                  = 3
  min_size                  = 2
  desired_capacity = 2
  health_check_grace_period = 300
  launch_template {
    id      = aws_launch_template.s3ha_launch_template.id
    version = "$Default"
  }
  vpc_zone_identifier = [aws_subnet.private1.id, aws_subnet.private2.id]
  target_group_arns = [aws_lb_target_group.deploy_tg.arn]

}

# database vm 

resource "aws_security_group" "db_security_group" {
  name        = "db-sg"
  description = "sg for database"
  vpc_id      = aws_vpc.main.id
  tags = {
    Name = "db-sg"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_network_interface" "network_interface" {
  subnet_id = aws_subnet.private2.id
  security_groups = [aws_security_group.db_security_group.id]
  tags = {
    Name = "db-network-interface"
  }
}

resource "aws_instance" "db" {
  ami           = "ami-08012c0a9ee8e21c4" # us-west-1
  instance_type = "t2.micro"
  key_name = "one"

  network_interface {
    network_interface_id = aws_network_interface.network_interface.id
    device_index         = 0
  }

  tags = {
    Name = "db-instance"
  } 
}

