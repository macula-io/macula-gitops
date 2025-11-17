# KinD Peer Cluster 2

GitOps manifests for the `macula-peer2` KinD cluster.

## Applications

- **macula-arcade**: Arcade game node that connects to bootstrap at bootstrap.macula.local

## Access

- Arcade UI: http://arcade2.macula.local
- MetalLB IP Pool: 192.168.129.80-89

## Deployment

```bash
kubectl --context kind-macula-peer2 apply -k dev/clusters/kind-macula-peer2
```
