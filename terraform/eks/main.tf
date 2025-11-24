terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Data sources to get VPC info
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["multi-tenant-vpc-budget"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Name"
    values = ["multi-tenant-public-*"]
  }
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "multi-tenant-cluster"
  cluster_version = "1.28"

  vpc_id     = data.aws_vpc.main.id
  subnet_ids = data.aws_subnets.public.ids

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Cluster endpoint access - public only for budget
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  # Minimal cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # SPOT Instance Node Group - 70% CHEAPER!
  eks_managed_node_groups = {
    spot_budget = {
      name = "spot-budget-nodes"
      
      desired_size = 3
      min_size     = 1
      max_size     = 4

      # Multiple instance types for spot availability
      instance_types = ["t3.micro", "t3a.micro", "t2.micro"]
      
      # SPOT = 70% discount!
      capacity_type  = "SPOT"

      # Disk size
      disk_size = 20  # Minimal disk

      labels = {
        role    = "general"
        pricing = "spot"
        env     = "budget"
      }

      tags = {
        Environment = "dev"
        CostOptimized = "true"
        "k8s.io/cluster-autoscaler/enabled" = "true"
        "k8s.io/cluster-autoscaler/multi-tenant-cluster" = "owned"
      }

      # Taints for spot instances (optional)
      taints = []
    }
  }

  # Cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    # Allow NodePort services
    ingress_nodeport = {
      description = "Allow NodePort services"
      protocol    = "tcp"
      from_port   = 30000
      to_port     = 32767
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = {
    Environment = "dev"
    CostCenter  = "budget-optimized"
    Terraform   = "true"
  }
}
