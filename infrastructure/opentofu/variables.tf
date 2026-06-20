variable "aws_region"    { default = "eu-south-1" }
variable "cluster_name"  { default = "shortener-cluster" }


variable "control_plane_instance_type" { default = "t3.small" }
variable "worker_instance_type"        { default = "t3.small" }
variable "worker_min_size"             { default = 2 }
variable "worker_max_size"             { default = 4 }
variable "worker_desired"              { default = 2 }

# ubuntu 26.04 in south-1
variable "ami_id" { default = "ami-09420cfad91ebef79" }