# MetalLB Setup for LAN Accessibility

## Overview

MetalLB is installed in the KinD cluster to provide LoadBalancer-type services with real LAN IPs, making services accessible from other machines on the network (like beam clusters).

## Architecture

```
Other Machines (beam00-03)
        ↓
   192.168.129.51:4433 (MetalLB assigned IP)
        ↓
   MetalLB L2 Advertisement
        ↓
   macula-bootstrap Service (LoadBalancer)
        ↓
   macula-bootstrap Pod (10.244.0.24:4433)
```

## Components

### 1. MetalLB Operator
- **Version**: v0.14.3
- **Namespace**: `metallb-system`
- **Components**:
  - Controller: Assigns IPs from pool
  - Speaker: Advertises IPs via L2 (ARP)

### 2. IP Address Pool
- **Name**: `lan-pool`
- **Range**: `192.168.129.50-192.168.129.60`
- **Protocol**: Layer 2 (ARP)
- **File**: `dev/clusters/kind-dev/metallb/ipaddresspool.yaml`

### 3. L2 Advertisement
- **Name**: `lan-advertisement`
- **Advertises**: All IPs in `lan-pool`
- **File**: `dev/clusters/kind-dev/metallb/l2advertisement.yaml`

## Bootstrap Service Configuration

### Service Type: LoadBalancer
```yaml
apiVersion: v1
kind: Service
metadata:
  name: macula-bootstrap
  namespace: macula
spec:
  type: LoadBalancer  # Changed from ClusterIP
  ports:
  - name: quic
    port: 4433
    targetPort: 4433
    protocol: UDP
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app: macula-bootstrap
```

### Assigned IP
- **External IP**: `192.168.129.51`
- **QUIC Port**: `4433/UDP`
- **HTTP Port**: `80/TCP` (for future use)

## DNS Configuration

### PowerDNS Record
- **Hostname**: `bootstrap.macula.local`
- **Type**: A
- **Value**: `192.168.129.3` (from Ingress annotation)
- **TTL**: 300 seconds
- **Managed by**: ExternalDNS (watches Ingress)

**Note**: The DNS currently points to `192.168.129.3` (primary host IP) because ExternalDNS is configured to watch Ingress resources, not Services. The bootstrap service is accessible via:
- Direct IP: `192.168.129.51:4433`
- Via hostname: `bootstrap.macula.local` → nginx-ingress → bootstrap pod

## DNS Override Issue

**Problem**: dnsmasq on the host has a hardcoded entry for `bootstrap.macula.local → 127.0.0.2`

**Solution**: Run the update script:
```bash
cd dev/infrastructure
sudo ./update-bootstrap-dns.sh
```

This removes the dnsmasq override, allowing PowerDNS to manage the record.

## Testing Accessibility

### From Local Machine
```bash
# Test QUIC port
nc -zvu 192.168.129.51 4433

# Should show: Connection to 192.168.129.51 4433 port [udp/*] succeeded!
```

### From Remote Machine (e.g., beam00)
```bash
# Test DNS resolution
dig +short bootstrap.macula.local

# Test QUIC connectivity
nc -zvu bootstrap.macula.local 4433
# or
nc -zvu 192.168.129.51 4433
```

## Verify MetalLB Status

```bash
# Check MetalLB pods
kubectl --context kind-macula-dev get pods -n metallb-system

# Check IP pool
kubectl --context kind-macula-dev get ipaddresspool -n metallb-system

# Check L2 advertisement
kubectl --context kind-macula-dev get l2advertisement -n metallb-system

# Check service external IP
kubectl --context kind-macula-dev get svc -n macula macula-bootstrap
```

## How It Works

1. **IP Assignment**: MetalLB controller assigns an IP from `lan-pool` (192.168.129.50-60) to the LoadBalancer service
2. **ARP Advertisement**: MetalLB speaker announces the IP via ARP, making the host respond to ARP requests for that IP
3. **Traffic Routing**:
   - External traffic to `192.168.129.51:4433` → Host network interface
   - kube-proxy routes to backend pods
   - Responds back through same path

4. **DNS Integration**: ExternalDNS watches Ingress and creates DNS records in PowerDNS

## Firewall Considerations

If the bootstrap service isn't accessible from other machines, check:

```bash
# Check if firewall is blocking
sudo ufw status

# Allow UDP 4433 if needed
sudo ufw allow 4433/udp

# Or disable firewall for testing
sudo ufw disable
```

## Why Not Docker Compose?

MetalLB **must run inside the Kubernetes cluster**, not in Docker Compose, because:

1. **Kubernetes Integration**: Needs access to Service resources and kube-proxy
2. **Per-Cluster Configuration**: Each cluster can have different IP pools
3. **IP Management**: Must coordinate with cluster networking (CNI)
4. **Load Balancing**: Works with kube-proxy for proper traffic distribution

## Future: Multiple Clusters

When deploying to beam clusters:

1. **Each cluster gets its own MetalLB**: Install MetalLB in each beam cluster
2. **Different IP pools**: Assign non-overlapping ranges:
   - KinD dev: `192.168.129.50-60`
   - beam00: `192.168.129.70-80`
   - beam01: `192.168.129.90-100`
   - etc.

3. **DNS Management**: ExternalDNS in each cluster creates records in PowerDNS

## Troubleshooting

### Service has no EXTERNAL-IP
```bash
# Check MetalLB logs
kubectl --context kind-macula-dev logs -n metallb-system -l app=metallb

# Check IP pool configuration
kubectl --context kind-macula-dev describe ipaddresspool -n metallb-system lan-pool
```

### ARP not working
```bash
# Check speaker logs
kubectl --context kind-macula-dev logs -n metallb-system -l component=speaker

# Verify L2 advertisement
kubectl --context kind-macula-dev describe l2advertisement -n metallb-system
```

### DNS still returns 127.0.0.2
```bash
# Run the DNS update script
sudo dev/infrastructure/update-bootstrap-dns.sh

# Verify dnsmasq config
cat /etc/dnsmasq.d/macula.conf | grep bootstrap

# Should return nothing
```

## Summary

✅ **MetalLB installed** in KinD cluster
✅ **IP pool configured** (192.168.129.50-60)
✅ **Bootstrap service** exposed as LoadBalancer
✅ **External IP assigned**: 192.168.129.51
✅ **QUIC port accessible**: UDP 4433
✅ **Ready for beam cluster access**

The bootstrap service is now accessible from any machine on the `192.168.129.0/23` network!
