#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}==>${NC} $1"
}

print_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

# Cluster configurations
declare -A CLUSTERS=(
    ["kind-macula-hub"]="80:80,443:443"
    ["kind-macula-peer0"]="8001:80,8443:443"
    ["kind-macula-peer1"]="8002:80,8444:443"
    ["kind-macula-peer2"]="8003:80,8445:443"
)

# Create registry network alias for all clusters
REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5000"

print_status "Creating Macula mesh clusters..."

for CLUSTER in kind-macula-hub kind-macula-peer0 kind-macula-peer1 kind-macula-peer2; do
    print_info "Creating cluster: ${CLUSTER}"

    # Get port mappings for this cluster
    PORTS=${CLUSTERS[$CLUSTER]}
    HTTP_PORT=$(echo $PORTS | cut -d',' -f1 | cut -d':' -f1)
    HTTPS_PORT=$(echo $PORTS | cut -d',' -f2 | cut -d':' -f1)

    # Create KinD cluster with registry and ingress port mappings
    cat <<EOF | kind create cluster --name ${CLUSTER#kind-} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: ${HTTP_PORT}
    protocol: TCP
  - containerPort: 443
    hostPort: ${HTTPS_PORT}
    protocol: TCP
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5001"]
    endpoint = ["http://${REGISTRY_NAME}:${REGISTRY_PORT}"]
EOF

    # Connect cluster to kind network (for registry access)
    print_info "Connecting ${CLUSTER} to kind network..."
    docker network connect kind ${CLUSTER}-control-plane 2>/dev/null || true

    # Connect to infrastructure network (for PowerDNS, TimescaleDB access)
    print_info "Connecting ${CLUSTER} to infrastructure network..."
    docker network connect infrastructure_macula-infra ${CLUSTER}-control-plane 2>/dev/null || true

    print_info "Cluster ${CLUSTER} created successfully"
    echo ""
done

print_status "All clusters created!"
print_info "Clusters:"
echo "  - kind-macula-hub (ports 80, 443)"
echo "  - kind-macula-peer0 (ports 8001, 8443)"
echo "  - kind-macula-peer1 (ports 8002, 8444)"
echo "  - kind-macula-peer2 (ports 8003, 8445)"
echo ""
print_info "Next steps:"
echo "  1. Deploy infrastructure to each cluster (nginx-ingress, metallb, external-dns)"
echo "  2. Deploy applications (bootstrap+console to hub, arcade to peers)"
echo "  3. Verify mesh connectivity"
