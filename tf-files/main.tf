// For simplicity, we will use only two AZs of the array (index 0 and 1). 
data "aws_availability_zones" "azs" {
    state = "available"
    filter {
        name   = "region-name"
        values = [var.aws_region]
    }
}

// NETWORK DEFINITIONS (VPC)
// -- VPC
resource "aws_vpc" "vpc-main" {
    cidr_block           = "${var.vpc_cidr}"
    enable_dns_support   = "true"
    enable_dns_hostnames = "true"
    instance_tenancy     = "default"
    tags = {
        Name = "vpc-main"
    }
}

// -- Private subnet for hosting two VM running nginx
resource "aws_subnet" "subnet-nginx-priv" {    
    depends_on              = [aws_vpc.vpc-main]
    vpc_id                  = aws_vpc.vpc-main.id
    cidr_block              = cidrsubnet("${var.vpc_cidr}", 3, 0)    
    availability_zone       = data.aws_availability_zones.azs.names[0]
    tags = {        
        Name  = "subnet-nginx"        
    }
}

// -- Private subnet for the private Network Load Balancer. 
resource "aws_subnet" "subnet-nlb-priv" {    
    depends_on              = [aws_vpc.vpc-main]
    vpc_id                  = aws_vpc.vpc-main.id
    cidr_block              = cidrsubnet("${var.vpc_cidr}", 3, 1)    
    availability_zone       = data.aws_availability_zones.azs.names[0]
    tags = {        
        Name  = "subnet-nlb"
    }
}

// -- Public Subnet for the ALB(1), NAT gateway and the jumpbox.
resource "aws_subnet" "subnet-alb-1-public" {    
    depends_on              = [aws_vpc.vpc-main]
    vpc_id                  = aws_vpc.vpc-main.id
    cidr_block              = cidrsubnet("${var.vpc_cidr}", 3, 2)    
    availability_zone       = data.aws_availability_zones.azs.names[0]
    tags = {        
        Name  = "subnet-alb-1"
    }
}

// -- Public Subnet for the ALB(2).
resource "aws_subnet" "subnet-alb-2-public" {    
    depends_on              = [aws_vpc.vpc-main]
    vpc_id                  = aws_vpc.vpc-main.id
    cidr_block              = cidrsubnet("${var.vpc_cidr}", 3, 3)    
    availability_zone       = data.aws_availability_zones.azs.names[1]
    tags = {        
        Name  = "subnet-alb-2"
    }
}

// -- Internet Gateway
resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.vpc-main.id
    tags = {        
        Name  = "igw"
    }
}

// -- NAT Gateway
resource "aws_eip" "eip-gw-nat" {    
    depends_on   = [aws_internet_gateway.igw]
    tags = {        
        Name  = "eip-gw-nat"
    }
}

resource "aws_nat_gateway" "natgw" {    
    allocation_id = aws_eip.eip-gw-nat.id
    subnet_id     = aws_subnet.subnet-alb-1-public.id    

    tags = {
        Name  = "gw-nat"
    }
}

// -- Private route table and associations to private networks 
resource "aws_route_table" "rt-private" {
    vpc_id = aws_vpc.vpc-main.id
    route {        
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.natgw.id
    }
    tags = {        
        Name = "rt-private"
    }
}

resource "aws_route_table_association" "rta-private-nginx" {
    subnet_id = aws_subnet.subnet-nginx-priv.id
    route_table_id = aws_route_table.rt-private.id
}

resource "aws_route_table_association" "rta-private-nlb" {
    subnet_id = aws_subnet.subnet-nlb-priv.id
    route_table_id = aws_route_table.rt-private.id
}

// -- Public route table and associations to public networks
resource "aws_route_table" "rt-public" {
    vpc_id = aws_vpc.vpc-main.id
    route {        
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {        
        Name = "rt-public"
    }
}

resource "aws_route_table_association" "rta-public-alb-1" {
    subnet_id = aws_subnet.subnet-alb-1-public.id
    route_table_id = aws_route_table.rt-public.id
}

resource "aws_route_table_association" "rta-public-alb-2" {
    subnet_id = aws_subnet.subnet-alb-2-public.id
    route_table_id = aws_route_table.rt-public.id
}

# VIRTUAL MACHINES

# -- Security group for HTTP 
resource "aws_security_group" "allow_http" {
  name        = "secgr-allow-http"
  description = "Allow HTTP inbound traffic"

  vpc_id = aws_vpc.vpc-main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all IPs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -- Security group for SSH
resource "aws_security_group" "allow_ssh" {
  name        = "secgr-allow-ssh"
  description = "Allow HTTP inbound traffic"

  vpc_id = aws_vpc.vpc-main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all IPs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -- VM keys
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vm-keys" {
    key_name   = "vm-keys"
    public_key = tls_private_key.ssh_key.public_key_openssh
    tags       = {        
        Name  = "vm-keys"
    }
}

# -- NGINX instances
resource "aws_instance" "nginx" {
    count                       = 2
    ami                         = var.vm_ami
    instance_type               = "t2.micro"
    subnet_id                   = aws_subnet.subnet-nginx-priv.id
    vpc_security_group_ids      = [aws_security_group.allow_http.id]
    associate_public_ip_address = false
    key_name                    = aws_key_pair.vm-keys.key_name

    # User Data to install nginx and set up a test page
    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y nginx
                systemctl start nginx
                systemctl enable nginx
                echo "<h1>Hello from NGINX on Terraform EC2 instance ${count.index + 1}</h1>" > /usr/share/nginx/html/index.html
                EOF

    tags = {
        Name = "vm-nginx-${count.index + 1}"
    }
}

# -- Jumpbox instance
resource "aws_instance" "jumpbox" { 
    ami                         = var.vm_ami
    instance_type               = "t2.micro"
    subnet_id                   = aws_subnet.subnet-alb-1-public.id
    vpc_security_group_ids      = [aws_security_group.allow_ssh.id]
    associate_public_ip_address = true
    key_name                    = aws_key_pair.vm-keys.key_name

    # User Data to install nginx and set up a test page
    user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y nmap-ncat                
                EOF
    tags = {
        Name = "vm-jumpbox"
    }
}

# NETWORK LOAD BALANCER
# -- Target group for NLB attached to EC2 NGINX instances
resource "aws_lb_target_group" "nginx_target_group" {
  name     = "nginx-target-group"
  port     = 80                      # Port for NGINX (HTTP)
  protocol = "TCP"                   # NLB operates on Layer 4, so TCP protocol is used
  vpc_id   = aws_vpc.vpc-main.id

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "nginx_tg_attachment" {
  count           = 2
  target_group_arn = aws_lb_target_group.nginx_target_group.arn
  target_id       = aws_instance.nginx[count.index].id
  port            = 80  # The port where NGINX is running
}

# -- Network Load Balancer definition (NLB)
resource "aws_lb" "nlb" {
  name               = "nginx-nlb"
  internal           = true  # Set to true if it's an internal NLB
  load_balancer_type = "network"  # NLB type
  subnets            = [aws_subnet.subnet-nlb-priv.id]  # Attach NLB to public subnets

  enable_deletion_protection = false
}

# -- TCP 80 TCP listener for the NLB
resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80  # Listen on HTTP port 80
  protocol          = "TCP"  # For NLB, the listener protocol is TCP

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx_target_group.arn
  }
}

# -- Data source for retrieving the private IP of the NLB
data "aws_network_interface" "nlb-network-interface" {
    filter {
        name   = "subnet-id"
        values = [ aws_subnet.subnet-nlb-priv.id ]
    }
}

# APPLICATION LOAD BALANCER
# -- Target group that uses IP addresses (NLB) as targets
resource "aws_lb_target_group" "alb_public_target_group" {
  name     = "alb-ip-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc-main.id
  target_type = "ip"  # IP target type

  health_check {
    interval            = 30
    path                = "/"
    port                = "80"
    protocol            = "HTTP"
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "tg_attachment_nlb" {
  target_group_arn = aws_lb_target_group.alb_public_target_group.arn
  target_id        = data.aws_network_interface.nlb-network-interface.private_ip
  port             = 80
}

# -- Application Load Balancer definition (ALB)
resource "aws_lb" "alb" {
    depends_on         = [ aws_lb.nlb ]
    name               = "public-alb"
    internal           = false  # This is a public ALB
    load_balancer_type = "application"
    security_groups    = [aws_security_group.allow_http.id]
    subnets            = [aws_subnet.subnet-alb-1-public.id, aws_subnet.subnet-alb-2-public.id]

    enable_deletion_protection = false
}

# -- HTTP 80 listener for the ALB
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_public_target_group.arn
  }
}