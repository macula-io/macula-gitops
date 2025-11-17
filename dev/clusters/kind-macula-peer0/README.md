# KinD Peer Cluster 0

GitOps manifests for the `macula-peer0` KinD cluster.

## Applications

- **macula-arcade**: Arcade game node that connects to bootstrap at bootstrap.macula.local

## Access

- Arcade UI: http://arcade0.macula.local
- MetalLB IP Pool: 192.168.129.60-69

## Deployment

```bash
kubectl --context kind-macula-peer0 apply -k dev/clusters/kind-macula-peer0
```
