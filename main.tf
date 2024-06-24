terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-2"
}

variable "cluster_name" {
  default = "my-eks-cluster"
}

variable "node_instance_type" {
  default = "t3.medium"
}

variable "desired_capacity" {
  default = 2
}

variable "max_size" {
  default = 3
}

variable "min_size" {
  default = 1
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

resource "aws_vpc" "eks_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_subnet" "eks_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "eks_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "${var.cluster_name}-route-table"
  }
}

resource "aws_route_table_association" "eks_route_table_association" {
  count          = 2
  subnet_id      = element(aws_subnet.eks_subnet.*.id, count.index)
  route_table_id = aws_route_table.eks_route_table.id
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.eks_subnet[*].id
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSServicePolicy,
  ]

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.eks_subnet[*].id

  scaling_config {
    desired_size = var.desired_capacity
    max_size     = var.max_size
    min_size     = var.min_size
  }

  instance_types = [var.node_instance_type]

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
  ]

  tags = {
    Name = "${var.cluster_name}-node-group"
  }
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

resource "local_file" "kubeconfig" {
  content  = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name = aws_eks_cluster.eks_cluster.name
    endpoint     = aws_eks_cluster.eks_cluster.endpoint
    ca_data      = aws_eks_cluster.eks_cluster.certificate_authority.0.data
    region       = var.region
  })
  filename = "${path.module}/kubeconfig-${aws_eks_cluster.eks_cluster.name}"
}

output "kubeconfig_filename" {
  value = local_file.kubeconfig.filename
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.name
}

output "cluster_endpoint" {
  description = "The endpoint of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_certificate_authority" {
  description = "The certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.certificate_authority.0.data
}

output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.id
}

output "node_group_name" {
  description = "The name of the EKS node group"
  value       = aws_eks_node_group.eks_node_group.node_group_name
}
