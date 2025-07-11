#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Confirm cleanup
confirm_cleanup() {
    print_header "Veeva SRE Assignment - Cleanup Script"
    print_warning "This will destroy all resources created by the deployment script."
    print_warning "This action cannot be undone!"
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Cleanup cancelled."
        exit 0
    fi
}

# Delete Kubernetes resources
cleanup_kubernetes() {
    print_header "Cleaning up Kubernetes Resources"
    
    # Check if kubectl is configured
    if ! kubectl cluster-info &> /dev/null; then
        print_warning "kubectl is not configured or cluster is not accessible. Skipping Kubernetes cleanup."
        return
    fi
    
    print_status "Deleting monitoring stack..."
    kubectl delete -f k8s/monitoring/grafana/ --ignore-not-found=true
    kubectl delete -f k8s/monitoring/prometheus/ --ignore-not-found=true
    
    print_status "Deleting applications..."
    kubectl delete -f k8s/backend/ --ignore-not-found=true
    kubectl delete -f k8s/frontend/ --ignore-not-found=true
    
    print_status "Deleting namespaces..."
    kubectl delete -f k8s/namespace.yaml --ignore-not-found=true
    kubectl delete -f k8s/monitoring/prometheus/namespace.yaml --ignore-not-found=true
    
    print_status "Kubernetes resources cleaned up!"
}

# Delete Docker images
cleanup_docker() {
    print_header "Cleaning up Docker Images"
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not available. Skipping Docker cleanup."
        return
    fi
    
    print_status "Removing Docker images..."
    docker rmi veeva/backend-app:latest --force 2>/dev/null || true
    docker rmi veeva/frontend-app:latest --force 2>/dev/null || true
    
    print_status "Docker images cleaned up!"
}

# Destroy Terraform infrastructure
cleanup_terraform() {
    print_header "Destroying Terraform Infrastructure"
    
    cd terraform
    
    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
        print_warning "Terraform is not initialized. Skipping Terraform cleanup."
        cd ..
        return
    fi
    
    print_status "Planning Terraform destruction..."
    terraform plan -destroy -out=destroy.tfplan
    
    print_status "Destroying Terraform infrastructure..."
    terraform apply destroy.tfplan
    
    print_status "Cleaning up Terraform files..."
    rm -f terraform.tfstate*
    rm -f tfplan destroy.tfplan
    rm -rf .terraform
    
    print_status "Terraform infrastructure destroyed!"
    
    cd ..
}

# Clean up kubectl configuration
cleanup_kubectl() {
    print_header "Cleaning up kubectl Configuration"
    
    # Try to get the cluster name from Terraform output first
    if [ -d "terraform/.terraform" ]; then
        cd terraform
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
        REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
        cd ..
    else
        CLUSTER_NAME="veeva-sre-cluster"
        REGION="eu-west-2"
    fi
    
    if [ -n "$CLUSTER_NAME" ] && [ -n "$REGION" ]; then
        print_status "Removing kubectl context for cluster: $CLUSTER_NAME"
        kubectl config delete-context "arn:aws:eks:$REGION:*:cluster/$CLUSTER_NAME" 2>/dev/null || true
        kubectl config delete-cluster "arn:aws:eks:$REGION:*:cluster/$CLUSTER_NAME" 2>/dev/null || true
        kubectl config unset "users.arn:aws:eks:$REGION:*:cluster/$CLUSTER_NAME" 2>/dev/null || true
    fi
    
    print_status "kubectl configuration cleaned up!"
}

# Clean up ECR repositories by deleting all images
cleanup_ecr() {
    print_header "Cleaning up ECR Repositories"
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        print_warning "AWS CLI is not available. Skipping ECR cleanup."
        return
    fi
    
    # Get repository names and region
    if [ -d "terraform/.terraform" ]; then
        cd terraform
        BACKEND_REPO=$(terraform output -raw ecr_backend_repository_name 2>/dev/null || echo "")
        FRONTEND_REPO=$(terraform output -raw ecr_frontend_repository_name 2>/dev/null || echo "")
        REGION=$(terraform output -raw aws_region 2>/dev/null || echo "eu-west-2")
        cd ..
    else
        BACKEND_REPO="veeva-sre-cluster-backend"
        FRONTEND_REPO="veeva-sre-cluster-frontend"
        REGION="eu-west-2"
    fi
    
    # Function to delete all images from a repository
    delete_ecr_images() {
        local repo_name=$1
        print_status "Deleting images from ECR repository: $repo_name"
        
        # Get all image tags
        local image_tags=$(aws ecr list-images --repository-name "$repo_name" --region "$REGION" --query 'imageIds[*].imageTag' --output text 2>/dev/null || echo "")
        
        if [ -n "$image_tags" ] && [ "$image_tags" != "None" ]; then
            # Delete images by tag
            for tag in $image_tags; do
                if [ "$tag" != "None" ]; then
                    print_status "Deleting image with tag: $tag"
                    aws ecr batch-delete-image --repository-name "$repo_name" --region "$REGION" --image-ids imageTag="$tag" >/dev/null 2>&1 || true
                fi
            done
        fi
        
        # Also delete any untagged images
        local untagged_images=$(aws ecr list-images --repository-name "$repo_name" --region "$REGION" --filter tagStatus=UNTAGGED --query 'imageIds[*].imageDigest' --output text 2>/dev/null || echo "")
        
        if [ -n "$untagged_images" ] && [ "$untagged_images" != "None" ]; then
            for digest in $untagged_images; do
                if [ "$digest" != "None" ]; then
                    print_status "Deleting untagged image with digest: ${digest:0:12}..."
                    aws ecr batch-delete-image --repository-name "$repo_name" --region "$REGION" --image-ids imageDigest="$digest" >/dev/null 2>&1 || true
                fi
            done
        fi
    }
    
    # Delete images from both repositories
    if [ -n "$BACKEND_REPO" ]; then
        delete_ecr_images "$BACKEND_REPO"
    fi
    
    if [ -n "$FRONTEND_REPO" ]; then
        delete_ecr_images "$FRONTEND_REPO"
    fi
    
    print_status "ECR repositories cleaned up!"
}

# Main cleanup function
main() {
    confirm_cleanup
    cleanup_kubernetes
    cleanup_docker
    cleanup_ecr
    cleanup_terraform
    cleanup_kubectl
    
    print_header "Cleanup Completed Successfully!"
    print_status "All resources have been cleaned up."
    print_status "Your AWS account should now be clean of all Veeva SRE assignment resources."
}

# Run main function
main "$@" 