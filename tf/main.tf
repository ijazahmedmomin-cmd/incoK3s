provider "aws" {
  region = "us-east-1"
}

resource "aws_key_pair" "ec2" {
  key_name   = "my-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

data "aws_ssm_parameter" "ubuntu_22" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

# ----------------------
# VPC
# ----------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# ----------------------
# Internet Gateway
# ----------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# ----------------------
# Public Subnets (2 AZs)
# ----------------------
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index + 1)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-${count.index}"
  }
}

data "aws_availability_zones" "available" {}

# ----------------------
# Public Route Table
# ----------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ----------------------
# Security group for k3s nodes + LB
# ----------------------
resource "aws_security_group" "k3s_sg" {
  name        = "k3s-sg"
  description = "Allow k3s + LB traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # app port
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k3s-sg"
  }
}


######################################
# TEST1 ALB
######################################
resource "aws_lb" "test1_lb" {
  name               = "test1-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.k3s_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "test1_tg" {
  name     = "test1-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "test1_listener" {
  load_balancer_arn = aws_lb.test1_lb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test1_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "test1_host1" {
  target_group_arn = aws_lb_target_group.test1_tg.arn
  target_id        = aws_instance.host1.id
  port             = 32080
}

resource "aws_lb_target_group_attachment" "test1_host2" {
  target_group_arn = aws_lb_target_group.test1_tg.arn
  target_id        = aws_instance.host2.id
  port             = 32080
}

######################################
# TEST2 ALB
######################################
resource "aws_lb" "test2_lb" {
  name               = "test2-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.k3s_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "test2_tg" {
  name     = "test2-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "test2_listener" {
  load_balancer_arn = aws_lb.test2_lb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test2_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "test2_host1" {
  target_group_arn = aws_lb_target_group.test2_tg.arn
  target_id        = aws_instance.host1.id
  port             = 32080
}

resource "aws_lb_target_group_attachment" "test2_host2" {
  target_group_arn = aws_lb_target_group.test2_tg.arn
  target_id        = aws_instance.host2.id
  port             = 32080
}




# ----------------------
# EC2 Instances (k3s nodes)
# ----------------------
resource "aws_instance" "host1" {
  ami                         = data.aws_ssm_parameter.ubuntu_22.value
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.k3s_sg.id]
  key_name                    = aws_key_pair.ec2.key_name
  associate_public_ip_address = true

  tags = {
    Name = "k3s-node-1"
  }
}

resource "aws_instance" "host2" {
  ami                         = data.aws_ssm_parameter.ubuntu_22.value
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public[1].id
  vpc_security_group_ids      = [aws_security_group.k3s_sg.id]
  key_name                    = aws_key_pair.ec2.key_name
  associate_public_ip_address = true

  tags = {
    Name = "k3s-node-2"
  }
}


output "test1_alb_dns_name" {
  description = "Public DNS of the Test1 ALB"
  value       = aws_lb.test1_lb.dns_name
}

output "test2_alb_dns_name" {
  description = "Public DNS of the Test2 ALB"
  value       = aws_lb.test2_lb.dns_name
}
