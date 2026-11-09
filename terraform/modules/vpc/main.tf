resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:Los flow logs se dejan fuera del laboratorio por costo; en un entorno real van a CloudWatch Logs o S3.
  cidr_block = var.cidr
  tags = {
    Name = "${var.environment}-vpc"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.environment}-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = element(var.availability_zones, count.index)

  tags = {
    Name = "${var.environment}-private-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.environment}-internet-gateway"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.environment}-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

#*******************NAT
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.environment}-nat-gateway"
  }
}

resource "aws_eip" "nat" {
  #checkov:skip=CKV2_AWS_19:La IP elástica está asociada al NAT Gateway, no a una instancia EC2.
  tags = {
    Name = "${var.environment}-nat-eip"
  }
  depends_on = [
    aws_internet_gateway.this
  ]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.environment}-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Deja el security group por defecto de la VPC sin reglas para que nada lo use por accidente.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "default-sin-reglas"
  }
}
