#!/usr/bin/env bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}==>${NC} $1"
}

print_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_ROOT="${SCRIPT_DIR}/../.."

print_status "Macula Mesh Deployment Script"
echo ""

# Step 1: Create all KinD clusters
print_status "Step 1: Creating KinD clusters..."
${SCRIPT_DIR}/create-mesh-clusters.sh

echo ""
print_status "Step 2: Deploying infrastructure and applications..."

# Deploy to hub cluster
print_info "Deploying to kind-macula-hub (bootstrap + console)..."
kubectl --context kind-macula-hub apply -k ${GITOPS_ROOT}/dev/clusters/kind-macula-hub

# Deploy to peer clusters
for i in 0 1 2; do
    print_info "Deploying to kind-macula-peer${i} (arcade)..."
    kubectl --context kind-macula-peer${i} apply -k ${GITOPS_ROOT}/dev/clusters/kind-macula-peer${i}
done

echo ""
print_status "Step 3: Waiting for pods to be ready..."

# Wait for hub pods
print_info "Waiting for hub cluster pods..."
kubectl --context kind-macula-hub wait --for=condition=ready pod -l app=macula-bootstrap -n macula --timeout=120s
kubectl --context kind-macula-hub wait --for=condition=ready pod -l app=macula-console -n macula --timeout=120s

# Wait for peer pods
for i in 0 1 2; do
    print_info "Waiting for peer${i} cluster pods..."
    kubectl --context kind-macula-peer${i} wait --for=condition=ready pod -l app=macula-arcade -n macula --timeout=120s || true
done

echo ""
print_status "Step 4: Checking service endpoints..."

print_info "Hub cluster services:"
kubectl --context kind-macula-hub get svc -n macula

for i in 0 1 2; do
    print_info "Peer${i} cluster services:"
    kubectl --context kind-macula-peer${i} get svc -n macula
done

echo ""
print_status "✓ Deployment complete!"
echo ""
print_info "Access points:"
echo "  - Console: http://console.macula.local"
echo "  - Bootstrap: http://bootstrap.macula.local"
echo "  - Arcade 0: http://arcade0.macula.local"
echo "  - Arcade 1: http://arcade1.macula.local"
echo "  - Arcade 2: http://arcade2.macula.local"
echo ""
print_info "Next steps:"
echo "  1. Update host nginx to route arcade{0,1,2}.macula.local"
echo "  2. Open console at http://console.macula.local to view mesh"
echo "  3. Check arcade nodes are connecting to bootstrap"
