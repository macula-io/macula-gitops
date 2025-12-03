# Macula GitOps - Production Environment

Production deployment manifests for the beam cluster (4 x k3s single-node clusters).

## Cluster Overview

| Cluster | IP | Memory | Storage | Role |
|---------|-----|--------|---------|------|
| beam00 | 192.168.1.10 | 16GB | 1x HDD + NVMe | Peer node |
| beam01 | 192.168.1.11 | 32GB | 2x HDD + NVMe | Peer node |
| beam02 | 192.168.1.12 | 32GB | 2x HDD + NVMe | Peer node |
| beam03 | 192.168.1.13 | 32GB | 2x HDD + NVMe | Peer node |

## Directory Structure

```
prod/
├── clusters/
│   ├── base/                    # Shared base manifests
│   │   └── apps/
│   │       └── arcade/          # Base arcade deployment
│   ├── beam00/                  # beam00-specific config
│   │   ├── apps/arcade/         # Kustomize overlay
│   │   ├── flux-system/         # FluxCD manifests (auto-generated)
│   │   └── kustomization.yaml
│   ├── beam01/                  # beam01-specific config
│   ├── beam02/                  # beam02-specific config
│   └── beam03/                  # beam03-specific config
├── infrastructure/              # Shared infrastructure (future)
├── scripts/                     # (empty - scripts in /infrastructure/scripts/)
└── README.md
```

## Prerequisites

1. **kubectl** configured with beam cluster kubeconfigs:
   ```bash
   ls ~/.kube/beam-clusters/
   # beam00.yaml beam01.yaml beam02.yaml beam03.yaml
   ```

2. **flux CLI** installed:
   ```bash
   curl -s https://fluxcd.io/install.sh | sudo bash
   ```

3. **Registry access** - beam clusters need to reach `registry.macula.local:5001`

## Quick Start

### Bootstrap FluxCD

```bash
# Set GitHub token (if private repo)
export GITHUB_TOKEN="ghp_xxxx"

# Bootstrap single cluster (from repo root)
./infrastructure/scripts/bootstrap-flux-beam.sh bootstrap beam00

# Bootstrap all clusters
./infrastructure/scripts/bootstrap-flux-beam.sh bootstrap all
```

Once bootstrapped, FluxCD will:
- Watch this repository for changes
- Automatically reconcile manifests every 60 seconds
- Report drift and sync status

### Check Status

```bash
# Check all clusters (from repo root)
./infrastructure/scripts/bootstrap-flux-beam.sh status all

# Check specific cluster
./infrastructure/scripts/bootstrap-flux-beam.sh status beam00
```

### Trigger Reconciliation

```bash
# Force FluxCD to sync immediately (from repo root)
./infrastructure/scripts/bootstrap-flux-beam.sh reconcile all
```

## Deployment Workflow (GitOps)

1. Make changes to manifests in this repository
2. Commit and push to GitHub
3. FluxCD automatically reconciles (every 60 seconds)
4. Or trigger manually: `./infrastructure/scripts/bootstrap-flux-beam.sh reconcile all`

**Build and push images:**
```bash
cd /path/to/macula-arcade
docker build -t registry.macula.local:5001/macula/arcade:latest .
docker push registry.macula.local:5001/macula/arcade:latest
# FluxCD will detect the new image and update pods
```

## Network Configuration

### Registry Access

Beam clusters on 192.168.1.x need to reach the registry on 192.168.129.x:

```yaml
# /etc/rancher/k3s/registries.yaml on each beam node
mirrors:
  "registry.macula.local:5001":
    endpoint:
      - "http://192.168.129.x:5001"
```

### Bootstrap URL

All arcade peers connect to bootstrap at `quic://bootstrap.macula.local:4433`

### Cross-Subnet Communication

- Beam subnet: 192.168.1.x
- Workstation subnet: 192.168.129.x
- These subnets can communicate directly (no NAT between them)

## Storage

Per CLAUDE.md guidelines, application data should use `/bulk` drives:

```yaml
# Example PersistentVolume (if needed)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: arcade-data
spec:
  capacity:
    storage: 10Gi
  hostPath:
    path: /bulk0/macula/arcade
    type: DirectoryOrCreate
```

## Monitoring

Check FluxCD status:
```bash
flux get all --kubeconfig ~/.kube/beam-clusters/beam00.yaml
```

Check pod logs:
```bash
kubectl --kubeconfig ~/.kube/beam-clusters/beam00.yaml logs -n macula -l app=macula-arcade
```

## Troubleshooting

### Cluster not accessible
```bash
# Verify SSH access
ssh rl@192.168.1.10 "kubectl get nodes"

# Check k3s status
ssh rl@192.168.1.10 "sudo systemctl status k3s"
```

### Image pull fails
```bash
# Check registry access from beam node
ssh rl@192.168.1.10 "curl http://registry.macula.local:5001/v2/_catalog"
```

### FluxCD sync issues
```bash
# Check FluxCD logs
kubectl --kubeconfig ~/.kube/beam-clusters/beam00.yaml logs -n flux-system deploy/source-controller
kubectl --kubeconfig ~/.kube/beam-clusters/beam00.yaml logs -n flux-system deploy/kustomize-controller
```

## Security

Production environment includes:
- Network policies
- RBAC configurations
- Secret management (sealed-secrets or external-secrets)
- TLS/certificates
- Resource limits and quotas
