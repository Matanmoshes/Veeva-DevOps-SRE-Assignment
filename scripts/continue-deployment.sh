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

# Build and push Docker images with improved buildx setup
build_and_push_images() {
    print_header "Building and Pushing Docker Images to ECR"
    
    cd terraform
    ECR_BACKEND_URL=$(terraform output -raw ecr_backend_repository_url)
    ECR_FRONTEND_URL=$(terraform output -raw ecr_frontend_repository_url)
    REGION=$(terraform output -raw aws_region)
    cd ..
    
    print_status "Authenticating with ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_BACKEND_URL
    
    # Setup Docker buildx more robustly
    print_status "Setting up Docker buildx for multi-platform builds..."
    
    # Remove existing builder if it exists in a bad state
    docker buildx rm multiplatform 2>/dev/null || true
    
    # Create new builder
    print_status "Creating new buildx builder..."
    docker buildx create --name multiplatform --use --driver docker-container
    
    # Bootstrap the builder
    print_status "Bootstrapping buildx builder..."
    docker buildx inspect --bootstrap
    
    print_status "Building and pushing backend image for linux/amd64..."
    cd docker/backend
    
    # Create a simple WAR file since we don't have Maven setup
    print_status "Creating simple ROOT.war for demo..."
    if [ ! -f "ROOT.war" ]; then
        mkdir -p temp/WEB-INF
        cp src/main/webapp/WEB-INF/web.xml temp/WEB-INF/
        cd temp
        jar cf ../ROOT.war WEB-INF/
        cd ..
        rm -rf temp
        cp ROOT.war app.war
    fi
    
    docker buildx build --platform linux/amd64 --push -t $ECR_BACKEND_URL:latest .
    cd ../..
    
    print_status "Building and pushing frontend image for linux/amd64..."
    cd docker/frontend
    docker buildx build --platform linux/amd64 --push -t $ECR_FRONTEND_URL:latest .
    cd ../..
    
    print_status "Docker images built and pushed successfully!"
}

# Update Kubernetes manifests with ECR image URLs
update_k8s_manifests() {
    print_header "Updating Kubernetes Manifests with ECR Image URLs"
    
    cd terraform
    ECR_BACKEND_URL=$(terraform output -raw ecr_backend_repository_url)
    ECR_FRONTEND_URL=$(terraform output -raw ecr_frontend_repository_url)
    cd ..
    
    print_status "Updating backend deployment with ECR image..."
    sed -i.bak "s|ECR_BACKEND_IMAGE_PLACEHOLDER|$ECR_BACKEND_URL:latest|g" k8s/backend/deployment.yaml
    
    print_status "Updating frontend deployment with ECR image..."
    sed -i.bak "s|ECR_FRONTEND_IMAGE_PLACEHOLDER|$ECR_FRONTEND_URL:latest|g" k8s/frontend/deployment.yaml
    
    print_status "Kubernetes manifests updated with ECR images!"
}

# Deploy applications to Kubernetes
deploy_applications() {
    print_header "Deploying Applications to Kubernetes"
    
    print_status "Creating namespaces..."
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/monitoring/prometheus/namespace.yaml
    
    print_status "Deploying backend application..."
    kubectl apply -f k8s/backend/
    
    print_status "Deploying frontend application..."
    kubectl apply -f k8s/frontend/
    
    print_status "Waiting for applications to be ready..."
    print_status "This may take 5-10 minutes for images to be pulled and pods to start..."
    
    kubectl wait --for=condition=available --timeout=600s deployment/backend-app -n veeva-sre
    kubectl wait --for=condition=available --timeout=600s deployment/frontend-app -n veeva-sre
    
    print_status "Applications deployed successfully!"
}

# Deploy monitoring stack
deploy_monitoring() {
    print_header "Deploying Monitoring Stack"
    
    print_status "Deploying Prometheus RBAC..."
    kubectl apply -f k8s/monitoring/prometheus/prometheus-rbac.yaml
    
    print_status "Deploying Prometheus configuration..."
    kubectl apply -f k8s/monitoring/prometheus/prometheus-config.yaml
    
    print_status "Deploying Prometheus..."
    kubectl apply -f k8s/monitoring/prometheus/prometheus-deployment.yaml
    
    print_status "Deploying Grafana configuration..."
    kubectl apply -f k8s/monitoring/grafana/grafana-config.yaml
    
    print_status "Deploying Grafana..."
    kubectl apply -f k8s/monitoring/grafana/grafana-deployment.yaml
    
    print_status "Waiting for monitoring stack to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring
    
    print_status "Monitoring stack deployed successfully!"
}

# Get service endpoints
get_endpoints() {
    print_header "Getting Service Endpoints"
    
    print_status "Waiting for LoadBalancer services to get external IPs..."
    print_warning "This may take 5-10 minutes for AWS LoadBalancers to provision..."
    
    # Wait for frontend LoadBalancer
    print_status "Waiting for frontend LoadBalancer..."
    kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' --timeout=600s service/frontend-service -n veeva-sre
    
    # Wait for backend LoadBalancer
    print_status "Waiting for backend LoadBalancer..."
    kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' --timeout=600s service/backend-service -n veeva-sre
    
    # Wait for Grafana LoadBalancer
    print_status "Waiting for Grafana LoadBalancer..."
    kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' --timeout=600s service/grafana-service -n monitoring
    
    # Wait for Prometheus LoadBalancer
    print_status "Waiting for Prometheus LoadBalancer..."
    kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' --timeout=600s service/prometheus-service -n monitoring
    
    print_status "Getting service endpoints..."
    
    # Frontend URL
    FRONTEND_URL=$(kubectl get svc frontend-service -n veeva-sre -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -z "$FRONTEND_URL" ]; then
        FRONTEND_URL=$(kubectl get svc frontend-service -n veeva-sre -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    fi
    
    # Backend URL
    BACKEND_URL=$(kubectl get svc backend-service -n veeva-sre -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -z "$BACKEND_URL" ]; then
        BACKEND_URL=$(kubectl get svc backend-service -n veeva-sre -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    fi
    
    # Grafana URL
    GRAFANA_URL=$(kubectl get svc grafana-service -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -z "$GRAFANA_URL" ]; then
        GRAFANA_URL=$(kubectl get svc grafana-service -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    fi
    
    # Prometheus URL
    PROMETHEUS_URL=$(kubectl get svc prometheus-service -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -z "$PROMETHEUS_URL" ]; then
        PROMETHEUS_URL=$(kubectl get svc prometheus-service -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    fi
    
    echo ""
    echo -e "${GREEN}🎉 DEPLOYMENT SUCCESSFUL! 🎉${NC}"
    echo -e "${GREEN}=== SERVICE ENDPOINTS ===${NC}"
    echo -e "${BLUE}Frontend URL:${NC} http://$FRONTEND_URL"
    echo -e "${BLUE}Backend URL:${NC} http://$BACKEND_URL"
    echo -e "${BLUE}Grafana URL:${NC} http://$GRAFANA_URL:3000 (admin/admin)"
    echo -e "${BLUE}Prometheus URL:${NC} http://$PROMETHEUS_URL:9090"
    echo -e "${GREEN}=========================${NC}"
    echo ""
    echo -e "${YELLOW}Note: It may take a few more minutes for all services to be fully operational.${NC}"
    echo -e "${YELLOW}You can test the backend health endpoint: curl http://$BACKEND_URL/health${NC}"
}

# Clean up temporary files
cleanup_temp_files() {
    print_status "Cleaning up temporary files..."
    
    # Restore original Kubernetes manifests
    if [ -f "k8s/backend/deployment.yaml.bak" ]; then
        mv k8s/backend/deployment.yaml.bak k8s/backend/deployment.yaml
    fi
    
    if [ -f "k8s/frontend/deployment.yaml.bak" ]; then
        mv k8s/frontend/deployment.yaml.bak k8s/frontend/deployment.yaml
    fi
    
    # Remove temporary WAR file
    if [ -f "docker/backend/ROOT.war" ]; then
        rm docker/backend/ROOT.war
    fi
}

# Error handling
handle_error() {
    print_error "Deployment failed! Cleaning up temporary files..."
    cleanup_temp_files
    exit 1
}

# Set error trap
trap handle_error ERR

# Main function
main() {
    print_header "Continuing Veeva SRE Assignment Deployment"
    print_status "Infrastructure is already deployed. Continuing with applications..."
    
    build_and_push_images
    update_k8s_manifests
    deploy_applications
    deploy_monitoring
    get_endpoints
    cleanup_temp_files
    
    print_header "Deployment Completed Successfully!"
    print_status "Your Veeva SRE assignment environment is now ready!"
    print_status "All services are accessible via the endpoints listed above."
}

# Run main function
main "$@" 