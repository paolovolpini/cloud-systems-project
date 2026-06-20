# il NLB mette i propri punti di load balancer nelle subnet pubbliche
# poi espone un nome DNS raggiungibile

resource "aws_lb" "main" {
  name               = "${var.cluster_name}-nlb"
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id
  internal           = false
  tags               = { Name = "${var.cluster_name}-nlb" }
}

# il NLB riceve il traffico on il listener
# e usa i target group per bilanciare il carico

resource "aws_lb_target_group" "http" {
  name     = "${var.cluster_name}-http"
  port     = 30080
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    protocol = "TCP"
    port     = 30080
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_target_group" "api" {
  name     = "${var.cluster_name}-api"
  port     = 6443
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    protocol = "TCP"
    port     = 6443
  }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.main.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}