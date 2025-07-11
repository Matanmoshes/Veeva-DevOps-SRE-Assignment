output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = module.eks.cluster_ca_certificate
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "EKS node security group ID"
  value       = module.eks.node_security_group_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "kubectl_config_command" {
  description = "Command to update kubectl config"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "ecr_backend_repository_url" {
  description = "ECR repository URL for backend application"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  description = "ECR repository URL for frontend application"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repository_name" {
  description = "ECR repository name for backend application"
  value       = aws_ecr_repository.backend.name
}

output "ecr_frontend_repository_name" {
  description = "ECR repository name for frontend application"
  value       = aws_ecr_repository.frontend.name
}

output "ecr_registry_id" {
  description = "ECR registry ID"
  value       = aws_ecr_repository.backend.registry_id
}

output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Add data source for current AWS account
data "aws_caller_identity" "current" {} 