variable "aws_region" {
    default = "eu-central-1"
    description   = "AWS region where to deploy."
    type = string
}

variable "vpc_cidr" {
    default = "10.0.0.0/24"
    description   = "VPC CIDR for the Experiment Nginx <- NLB <- ALB"
}

variable "vm_ami" {
    default       = "ami-00f07845aed8c0ee7"
    description   = "Amazon AWS AMI for VMs"
}