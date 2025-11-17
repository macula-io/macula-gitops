#!/usr/bin/env bash
set -e

# Usage: ./setup-peer-cluster.sh <peer-number>
# Example: ./setup-peer-cluster.sh 0

PEER_NUM=$1

if [ -z "$PEER_NUM" ]; then
    echo "Usage: $0 <peer-number>"
    echo "Example: $0 0"
    exit 1
fi

CLUSTER_DIR="/home/rl/work/github.com/macula-io/macula-gitops/dev/clusters/kind-macula-peer${PEER_NUM}"
HUB_DIR="/home/rl/work/github.com/macula-io/macula-gitops/dev/clusters/kind-macula-hub"

echo "Setting up GitOps manifests for kind-macula-peer${PEER_NUM}..."

# Copy infrastructure from hub (same for all clusters)
cp -r ${HUB_DIR}/infrastructure ${CLUSTER_DIR}/

# Update MetalLB IP pool for this peer
FIRST_IP=$((60 + (PEER_NUM * 10)))
LAST_IP=$((FIRST_IP + 9))
sed -i "s/192.168.129.50-192.168.129.60/192.168.129.${FIRST_IP}-192.168.129.${LAST_IP}/" \
    ${CLUSTER_DIR}/infrastructure/metallb/ipaddresspool.yaml

echo "  - Updated MetalLB IP pool: 192.168.129.${FIRST_IP}-${LAST_IP}"

# Create arcade app directory
mkdir -p ${CLUSTER_DIR}/apps/arcade

# Create arcade namespace
cat > ${CLUSTER_DIR}/apps/arcade/namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: macula
EOF

# Create arcade deployment
cat > ${CLUSTER_DIR}/apps/arcade/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: macula-arcade
  namespace: macula
spec:
  replicas: 1
  selector:
    matchLabels:
      app: macula-arcade
  template:
    metadata:
      labels:
        app: macula-arcade
    spec:
      containers:
      - name: arcade
        image: localhost:5001/macula/arcade:latest
        imagePullPolicy: Always
        ports:
        - name: http
          containerPort: 4000
          protocol: TCP
        env:
        - name: PORT
          value: "4000"
        - name: PHX_HOST
          value: "arcade${PEER_NUM}.macula.local"
        - name: BOOTSTRAP_URL
          value: "http://bootstrap.macula.local"
        - name: PEER_ID
          value: "peer${PEER_NUM}"
        livenessProbe:
          httpGet:
            path: /
            port: 4000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 4000
          initialDelaySeconds: 10
          periodSeconds: 5
EOF

# Create arcade service
cat > ${CLUSTER_DIR}/apps/arcade/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: macula-arcade
  namespace: macula
spec:
  type: LoadBalancer
  ports:
  - name: http
    port: 80
    targetPort: 4000
    protocol: TCP
  selector:
    app: macula-arcade
EOF

# Create arcade ingress
cat > ${CLUSTER_DIR}/apps/arcade/ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: macula-arcade
  namespace: macula
  annotations:
    external-dns.alpha.kubernetes.io/hostname: arcade${PEER_NUM}.macula.local
spec:
  ingressClassName: nginx
  rules:
  - host: arcade${PEER_NUM}.macula.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: macula-arcade
            port:
              number: 80
EOF

# Create arcade kustomization
cat > ${CLUSTER_DIR}/apps/arcade/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: macula

resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
EOF

# Create root kustomization for peer cluster
cat > ${CLUSTER_DIR}/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  # Infrastructure components (installed first)
  - infrastructure/nginx-ingress
  - infrastructure/metallb
  - infrastructure/external-dns

  # Application deployments
  - apps/arcade
EOF

# Create README
cat > ${CLUSTER_DIR}/README.md <<EOF
# KinD Peer Cluster ${PEER_NUM}

GitOps manifests for the \`macula-peer${PEER_NUM}\` KinD cluster.

## Applications

- **macula-arcade**: Arcade game node that connects to bootstrap at bootstrap.macula.local

## Access

- Arcade UI: http://arcade${PEER_NUM}.macula.local
- MetalLB IP Pool: 192.168.129.${FIRST_IP}-${LAST_IP}

## Deployment

\`\`\`bash
kubectl --context kind-macula-peer${PEER_NUM} apply -k dev/clusters/kind-macula-peer${PEER_NUM}
\`\`\`
EOF

echo "✓ Peer cluster ${PEER_NUM} manifests created at ${CLUSTER_DIR}"
echo "  - Arcade will be accessible at: http://arcade${PEER_NUM}.macula.local"
echo "  - MetalLB IP pool: 192.168.129.${FIRST_IP}-${LAST_IP}"
