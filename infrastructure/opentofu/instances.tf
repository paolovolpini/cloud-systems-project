# ogni istanza ha un instance profile che permette di definire 
# il ruolo di ogni istanza, definiti in iam.tf

# il control plane è solo e non scala

resource "aws_instance" "control_plane" {
  ami                    = var.ami_id
  instance_type          = var.control_plane_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.k8s.id]
  iam_instance_profile   = aws_iam_instance_profile.control_plane.name

  depends_on = [aws_nat_gateway.main]

  
  user_data = base64encode(templatefile("${path.module}/control-plane-userdata.tftpl", {
    aws_region   = var.aws_region
    nlb_dns      = aws_lb.main.dns_name
    pod_cidr     = "10.244.0.0/16" # cidr di flannel
  }))

  tags = { Name = "${var.cluster_name}-control-plane" }
}

# come endpoint del cluster k8s si specifica il NLB
# quindi il control plane dev'essere agganciato al NLB 

resource "aws_lb_target_group_attachment" "control_plane_api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.control_plane.id
  port             = 6443
}


# per i worker basta un template per lanciare le macchine dell'ASG
resource "aws_launch_template" "workers" {
  name_prefix   = "${var.cluster_name}-worker-"
  image_id      = var.ami_id
  instance_type = var.worker_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.workers.name
  }

  vpc_security_group_ids = [aws_security_group.k8s.id]

  # bisogna encodare in base64
  user_data = base64encode(templatefile("${path.module}/worker-userdata.tftpl", {
    aws_region   = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.cluster_name}-worker" }
  }
}

resource "aws_autoscaling_group" "workers" {
  name                = "${var.cluster_name}-workers-asg"
  min_size            = var.worker_min_size
  max_size            = var.worker_max_size
  desired_capacity    = var.worker_desired
  # splat operator (https://opentofu.org/docs/language/expressions/splat/)
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.http.arn]

  depends_on = [aws_nat_gateway.main]

  launch_template {
    id      = aws_launch_template.workers.id
    version = "$Latest"
  }

  # la modifica ai template viene resa rolling allo stesso modo con cui 
  # le repliche del cluster k8s vengono aggiornate, mantenendo il 50% delle instances up
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker"
    propagate_at_launch = true
  }
}