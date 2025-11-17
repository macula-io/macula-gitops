# KinD Peer Cluster 1

GitOps manifests for the `macula-peer1` KinD cluster.

## Applications

- **macula-arcade**: Arcade game node that connects to bootstrap at bootstrap.macula.local

## Access

- Arcade UI: http://arcade1.macula.local
- MetalLB IP Pool: 192.168.129.70-79

## Deployment

```bash
kubectl --context kind-macula-peer1 apply -k dev/clusters/kind-macula-peer1
```
