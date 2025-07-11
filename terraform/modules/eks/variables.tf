variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
}

variable "node_desired_capacity" {
  description = "Desired number of nodes in the EKS node group"
  type        = number
}

variable "node_max_capacity" {
  description = "Maximum number of nodes in the EKS node group"
  type        = number
}

variable "node_min_capacity" {
  description = "Minimum number of nodes in the EKS node group"
  type        = number
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "ssh_key_name" {
  description = "EC2 Key Pair name for SSH access to nodes (optional)"
  type        = string
  default     = ""
} 