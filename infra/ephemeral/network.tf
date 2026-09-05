# Public subnet only, no NAT gateway (~$32/month we don't need for a
# single node that only needs outbound internet for pulling images/apt
# packages and inbound for the demo port).

resource "aws_vpc" "main" {
  # Must NOT overlap k3s/flannel's default pod CIDR (10.42.0.0/16) or
  # service CIDR (10.43.0.0/16) — the VPC's own DNS resolver lives at
  # <vpc-cidr-base>+2, and if that address falls inside the pod network,
  # cluster routing hijacks it: DNS queries meant for the real AWS
  # resolver loop back into the pod network instead, which is exactly
  # what CoreDNS's loop-detection was catching (every pod on the cluster
  # lost external DNS as a result). 10.50.0.0/16 avoids both.
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Tightly scoped: no inbound SSH at all (administration goes through SSM
# Session Manager / Run Command, which needs no open inbound port). Only
# the k8s NodePort used to demo the API is open, and only to your own IP.
resource "aws_security_group" "node" {
  name        = "${var.project_name}-node"
  description = "k3s node: demo NodePort from operator IP only, all egress"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Agent API NodePort (operator IP only)"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-node-sg" }
}
