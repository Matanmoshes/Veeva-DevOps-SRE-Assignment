#!/bin/bash

# Veeva SRE Assignment - Deployment Validation Script
# Quick verification that all components are working correctly

set -e

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "================================"
echo "🔍 Veeva SRE Deployment Validation"
echo "================================"

# Check if we're in the right directory
if [ ! -f "terraform/main.tf" ]; then
    print_error "Please run this script from the veeva-sre directory"
    exit 1
fi

# Get infrastructure status
print_status "Checking infrastructure status..."
cd terraform
if ! terraform output -raw aws_region &>/dev/null; then
    print_error "Terraform infrastructure not found. Please run ./scripts/deploy.sh first"
    exit 1
fi

REGION=$(terraform output -raw aws_region)
print_success "Infrastructure found in region: $REGION"
cd ..

# Check EKS cluster
print_status "Checking EKS cluster connectivity..."
if ! kubectl get nodes &>/dev/null; then
    print_error "Cannot connect to EKS cluster"
    exit 1
fi

NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
print_success "EKS cluster accessible with $NODE_COUNT nodes"

# Check application pods
print_status "Checking application pods..."
BACKEND_PODS=$(kubectl get pods -n veeva-sre -l app=backend-app --no-headers 2>/dev/null | grep Running | wc -l)
FRONTEND_PODS=$(kubectl get pods -n veeva-sre -l app=frontend-app --no-headers 2>/dev/null | grep Running | wc -l)

if [ "$BACKEND_PODS" -eq 0 ] || [ "$FRONTEND_PODS" -eq 0 ]; then
    print_error "Application pods not running. Backend: $BACKEND_PODS/2, Frontend: $FRONTEND_PODS/2"
    exit 1
fi

print_success "Application pods running - Backend: $BACKEND_PODS/2, Frontend: $FRONTEND_PODS/2"

# Check monitoring pods
print_status "Checking monitoring stack..."
PROMETHEUS_PODS=$(kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | grep Running | wc -l)
GRAFANA_PODS=$(kubectl get pods -n monitoring -l app=grafana --no-headers 2>/dev/null | grep Running | wc -l)

if [ "$PROMETHEUS_PODS" -eq 0 ] || [ "$GRAFANA_PODS" -eq 0 ]; then
    print_warning "Monitoring pods not fully ready. Prometheus: $PROMETHEUS_PODS/1, Grafana: $GRAFANA_PODS/1"
else
    print_success "Monitoring stack running - Prometheus: $PROMETHEUS_PODS/1, Grafana: $GRAFANA_PODS/1"
fi

# Get service URLs
print_status "Getting service URLs..."
FRONTEND_URL=$(kubectl get service -n veeva-sre frontend-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
BACKEND_URL=$(kubectl get service -n veeva-sre backend-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
GRAFANA_URL=$(kubectl get service -n monitoring grafana-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
PROMETHEUS_URL=$(kubectl get service -n monitoring prometheus-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ -z "$FRONTEND_URL" ] || [ -z "$BACKEND_URL" ]; then
    print_error "LoadBalancer URLs not ready yet. Please wait a few minutes and try again."
    exit 1
fi

# Test backend API endpoints
print_status "Testing backend API endpoints..."
if curl -s --max-time 10 "http://$BACKEND_URL/health" | jq -e '.status == "healthy"' &>/dev/null; then
    print_success "✅ Backend /health endpoint working"
else
    print_error "❌ Backend /health endpoint failed"
fi

if curl -s --max-time 10 "http://$BACKEND_URL/info" | jq -e '.application' &>/dev/null; then
    print_success "✅ Backend /info endpoint working"
else
    print_error "❌ Backend /info endpoint failed"
fi

if curl -s --max-time 10 "http://$BACKEND_URL/metrics" | grep -q "jvm_memory_heap_used_bytes"; then
    print_success "✅ Backend /metrics endpoint working (Prometheus format)"
else
    print_error "❌ Backend /metrics endpoint failed"
fi

# Test frontend
print_status "Testing frontend..."
if curl -s --max-time 10 "http://$FRONTEND_URL" | grep -q "Veeva SRE"; then
    print_success "✅ Frontend accessible"
else
    print_error "❌ Frontend not accessible"
fi

echo ""
echo "================================"
echo "🎉 Deployment Validation Complete"
echo "================================"
echo ""
echo "📋 Access URLs:"
echo "🌐 Frontend:   http://$FRONTEND_URL"
echo "🔧 Backend:    http://$BACKEND_URL"
echo "📊 Grafana:    http://$GRAFANA_URL:3000 (admin/admin)"
echo "📈 Prometheus: http://$PROMETHEUS_URL:9090"
echo ""
echo "🧪 API Test Commands:"
echo "curl http://$BACKEND_URL/health"
echo "curl http://$BACKEND_URL/info"
echo "curl http://$BACKEND_URL/metrics"
echo ""
print_success "All systems operational! 🚀" 