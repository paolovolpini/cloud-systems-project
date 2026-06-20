data "aws_availability_zones" "available" {
  state = "available"
}

# vpc main utilizzata per le ec2

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.cluster_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.cluster_name}-igw" }
}

# due subnet pubbliche e private, le pubbliche per il nlb in nlb.tf

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index] # una subnet per az per HA
  map_public_ip_on_launch = true # si assegna public ip su questa subnet
  tags = { Name = "${var.cluster_name}-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${var.cluster_name}-private-${count.index}" }
}

# ho visto che senza il NAT gateway il pull delle immagini diventa impossibile

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.cluster_name}-nat" }
  # in teoria non è necessaria perché la definizione sta già sopra
  # ma non si sa mai per evitare attivazioni (e quindi spese) inutili
  depends_on    = [aws_internet_gateway.main]
}

# questa è la route pubblica, cioè verso la rete
# tofu richiede la definizione di un oggetto route dove si specifica blocco cidr e l'id dell' igw
# però di per sè non associa la route table, per cui ci vuole anche una route table association

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.cluster_name}-public-rt" }
}


resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# la stessa cosa per la privata
# si specifica il nat gateway in questo caso 
# altrimenti le macchine sono raggiungibili da internet e non sarebbe privata

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${var.cluster_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}