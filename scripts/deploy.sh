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

# Function to wait with spinner
wait_with_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker buildx is available (for multi-platform builds)
    if ! docker buildx version &> /dev/null; then
        print_error "Docker buildx is not available. Please update Docker to a newer version."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region || echo "eu-west-2")
    
    print_status "All prerequisites are met!"
    print_status "AWS Account ID: $AWS_ACCOUNT_ID"
    print_status "AWS Region: $AWS_REGION"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    print_header "Deploying Infrastructure with Terraform"
    
    cd terraform
    
    print_status "Initializing Terraform..."
    terraform init
    
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    print_status "Applying Terraform configuration..."
    print_warning "This will take 10-15 minutes for EKS cluster creation..."
    terraform apply tfplan
    
    print_status "Getting Terraform outputs..."
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw aws_region)
    ECR_BACKEND_URL=$(terraform output -raw ecr_backend_repository_url)
    ECR_FRONTEND_URL=$(terraform output -raw ecr_frontend_repository_url)
    ACCOUNT_ID=$(terraform output -raw account_id)
    
    print_status "Infrastructure deployed successfully!"
    print_status "Cluster: $CLUSTER_NAME"
    print_status "Region: $REGION"
    print_status "Backend ECR: $ECR_BACKEND_URL"
    print_status "Frontend ECR: $ECR_FRONTEND_URL"
    
    cd ..
}

# Wait for EKS cluster to be ready
wait_for_cluster() {
    print_header "Waiting for EKS Cluster to be Ready"
    
    cd terraform
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw aws_region)
    cd ..
    
    print_status "Checking cluster status..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(aws eks describe-cluster --region $REGION --name $CLUSTER_NAME --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$status" = "ACTIVE" ]; then
            print_status "Cluster is ACTIVE!"
            break
        elif [ "$status" = "FAILED" ]; then
            print_error "Cluster creation failed!"
            exit 1
        else
            print_status "Cluster status: $status (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_error "Cluster did not become ready within expected time"
        exit 1
    fi
}

# Configure kubectl
configure_kubectl() {
    print_header "Configuring kubectl"
    
    cd terraform
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw aws_region)
    cd ..
    
    print_status "Updating kubeconfig..."
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
    
    print_status "Waiting for nodes to be ready..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep Ready | wc -l || echo "0")
        
        if [ "$ready_nodes" -ge "1" ]; then
            print_status "Nodes are ready!"
            kubectl get nodes
            break
        else
            print_status "Waiting for nodes... (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_error "Nodes did not become ready within expected time"
        exit 1
    fi
}

# Authenticate with ECR and build/push Docker images
build_and_push_images() {
    print_header "Building and Pushing Docker Images to ECR"
    
    cd terraform
    ECR_BACKEND_URL=$(terraform output -raw ecr_backend_repository_url)
    ECR_FRONTEND_URL=$(terraform output -raw ecr_frontend_repository_url)
    REGION=$(terraform output -raw aws_region)
    cd ..
    
    print_status "Authenticating with ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_BACKEND_URL
    
    # Create multi-platform builder if it doesn't exist
    print_status "Setting up Docker buildx for multi-platform builds..."
    if ! docker buildx inspect multiplatform >/dev/null 2>&1; then
        print_status "Creating new buildx builder..."
        docker buildx create --name multiplatform --use
    else
        print_status "Using existing buildx builder..."
        docker buildx use multiplatform
    fi
    
    print_status "Building and pushing backend image for linux/amd64..."
    cd docker/backend
    
    # Create a proper WAR file with compiled servlets
    print_status "Creating backend WAR file with API endpoints..."
    
    # Check if Java is available and set PATH if needed
    if ! command -v java &> /dev/null; then
        if [ -d "/opt/homebrew/opt/openjdk@11/bin" ]; then
            export PATH="/opt/homebrew/opt/openjdk@11/bin:$PATH"
        elif [ -d "/usr/lib/jvm/java-11-openjdk/bin" ]; then
            export PATH="/usr/lib/jvm/java-11-openjdk/bin:$PATH"
        else
            print_error "Java 11 not found. Please install Java 11 (brew install openjdk@11 on macOS)"
            exit 1
        fi
    fi
    
    # Create proper WAR with compiled servlets if not exists
    if [ ! -f "WEB-INF/classes/com/veeva/sre/HealthServlet.class" ]; then
        print_status "Downloading servlet API and compiling servlets..."
        if [ ! -f "servlet-api.jar" ]; then
            curl -L -o servlet-api.jar "https://repo1.maven.org/maven2/javax/servlet/javax.servlet-api/4.0.1/javax.servlet-api-4.0.1.jar"
        fi
        
        mkdir -p WEB-INF/classes
        javac -cp servlet-api.jar -d WEB-INF/classes src/main/java/com/veeva/sre/*.java
        cp src/main/webapp/WEB-INF/web.xml WEB-INF/
        echo '<!DOCTYPE html><html><head><title>Veeva SRE Backend</title></head><body><h1>Veeva SRE Backend Service</h1><p>API endpoints: /health, /info, /metrics</p></body></html>' > index.html
    fi
    
    # Create final WAR file
    jar -cvf ROOT.war index.html WEB-INF/
    cp ROOT.war app.war
    
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
    echo ""
    echo "================================"
    echo "📋 COMPONENT ACCESS URLS"
    echo "================================"
    echo ""
    echo -e "🌐 ${BLUE}Frontend Application:${NC}"
    echo "   http://$FRONTEND_URL"
    echo ""
    echo -e "🔧 ${BLUE}Backend API:${NC}"
    echo "   Base URL: http://$BACKEND_URL"
    echo "   Health:   http://$BACKEND_URL/health"
    echo "   Info:     http://$BACKEND_URL/info"
    echo "   Metrics:  http://$BACKEND_URL/metrics"
    echo ""
    echo -e "📊 ${BLUE}Grafana Dashboard:${NC}"
    echo "   http://$GRAFANA_URL:3000"
    echo "   Login: admin/admin"
    echo ""
    echo -e "📈 ${BLUE}Prometheus:${NC}"
    echo "   http://$PROMETHEUS_URL:9090"
    echo ""
    echo "🧪 Quick Validation:"
    echo "   ./scripts/validate-deployment.sh"
    echo ""
    echo "🔄 To get URLs anytime:"
    echo "   kubectl get services -n veeva-sre"
    echo "   kubectl get services -n monitoring"
    echo ""
    echo "🧹 To clean up everything:"
    echo "   ./scripts/cleanup.sh"
    echo ""
    echo -e "${GREEN}All systems operational! 🚀${NC}"
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

# Main deployment function
main() {
    print_header "Veeva SRE Assignment - Enhanced Deployment Script"
    print_status "Starting deployment with ECR integration and proper timing..."
    
    check_prerequisites
    deploy_infrastructure
    wait_for_cluster
    configure_kubectl
    build_and_push_images
    update_k8s_manifests
    deploy_applications
    deploy_monitoring
    get_endpoints
    cleanup_temp_files
    
    print_header "Deployment Completed Successfully!"
    print_status "Your Veeva SRE assignment environment is now ready!"
    print_status "All services are accessible via the endpoints listed above."
    print_status "Total deployment time: approximately 25-35 minutes."
}

# Run main function
main "$@" 