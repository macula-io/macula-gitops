#!/bin/bash
#
# Bootstrap FluxCD on beam clusters
#
# Usage: ./bootstrap-flux-beam.sh <command> [cluster]
#
# Prerequisites:
#   - flux CLI installed
#   - kubectl configured with beam cluster kubeconfigs
#   - GITHUB_TOKEN environment variable set (for private repos)
#
# For public repos, you can skip the GITHUB_TOKEN

set -euo pipefail

KUBECONFIG_DIR="${HOME}/.kube/beam-clusters"

# GitHub repository details
GITHUB_OWNER="${GITHUB_OWNER:-macula-io}"
GITHUB_REPO="${GITHUB_REPO:-macula-gitops}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

# Beam cluster IPs
declare -A BEAM_IPS=(
    ["beam00"]="192.168.1.10"
    ["beam01"]="192.168.1.11"
    ["beam02"]="192.168.1.12"
    ["beam03"]="192.168.1.13"
)

check_prerequisites() {
    echo "Checking prerequisites..."

    if ! command -v flux &> /dev/null; then
        echo "ERROR: flux CLI not found. Install with: curl -s https://fluxcd.io/install.sh | sudo bash"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        echo "ERROR: kubectl not found"
        exit 1
    fi

    echo "Prerequisites OK"
}

check_cluster_access() {
    local cluster="$1"
    local kubeconfig="${KUBECONFIG_DIR}/${cluster}.yaml"

    if [[ ! -f "$kubeconfig" ]]; then
        echo "ERROR: Kubeconfig not found: $kubeconfig"
        return 1
    fi

    if ! kubectl --kubeconfig="$kubeconfig" get nodes &>/dev/null; then
        echo "ERROR: Cannot access cluster $cluster"
        return 1
    fi

    echo "Cluster $cluster accessible"
    return 0
}

bootstrap_cluster() {
    local cluster="$1"
    local kubeconfig="${KUBECONFIG_DIR}/${cluster}.yaml"
    local flux_path="prod/clusters/${cluster}"

    echo ""
    echo "=========================================="
    echo "Bootstrapping FluxCD on ${cluster}"
    echo "=========================================="

    if ! check_cluster_access "$cluster"; then
        echo "Skipping $cluster - not accessible"
        return 1
    fi

    # Check if flux is already installed and pointing to correct repo
    if kubectl --kubeconfig="$kubeconfig" get namespace flux-system &>/dev/null; then
        local current_repo
        current_repo=$(kubectl --kubeconfig="$kubeconfig" get gitrepository -n flux-system flux-system -o jsonpath='{.spec.url}' 2>/dev/null || echo "")

        if [[ "$current_repo" == *"${GITHUB_REPO}"* ]]; then
            echo "FluxCD already configured for ${GITHUB_REPO}"
            echo "Triggering reconciliation..."
            flux reconcile source git flux-system --kubeconfig="$kubeconfig" 2>/dev/null || true
            return 0
        else
            echo "FluxCD installed but pointing to different repo: $current_repo"
            echo "To reconfigure, first run: flux uninstall --kubeconfig=$kubeconfig"
            return 1
        fi
    fi

    echo "Installing FluxCD on $cluster..."
    echo "  Repository: ${GITHUB_OWNER}/${GITHUB_REPO}"
    echo "  Branch: ${GITHUB_BRANCH}"
    echo "  Path: ${flux_path}"

    # Bootstrap FluxCD
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        flux bootstrap github \
            --kubeconfig="$kubeconfig" \
            --owner="$GITHUB_OWNER" \
            --repository="$GITHUB_REPO" \
            --branch="$GITHUB_BRANCH" \
            --path="$flux_path" \
            --personal \
            --token-auth
    else
        flux bootstrap github \
            --kubeconfig="$kubeconfig" \
            --owner="$GITHUB_OWNER" \
            --repository="$GITHUB_REPO" \
            --branch="$GITHUB_BRANCH" \
            --path="$flux_path" \
            --personal
    fi

    echo "FluxCD bootstrapped on $cluster"
}

reconcile_cluster() {
    local cluster="$1"
    local kubeconfig="${KUBECONFIG_DIR}/${cluster}.yaml"

    echo ""
    echo "=== Reconciling ${cluster} ==="

    if ! check_cluster_access "$cluster"; then
        return 1
    fi

    if ! kubectl --kubeconfig="$kubeconfig" get namespace flux-system &>/dev/null; then
        echo "FluxCD not installed on $cluster - run 'bootstrap' first"
        return 1
    fi

    echo "Triggering git source reconciliation..."
    flux reconcile source git flux-system --kubeconfig="$kubeconfig"

    echo "Triggering kustomization reconciliation..."
    flux reconcile kustomization flux-system --kubeconfig="$kubeconfig"

    echo "Reconciliation triggered for $cluster"
}

show_status() {
    local cluster="$1"
    local kubeconfig="${KUBECONFIG_DIR}/${cluster}.yaml"

    echo ""
    echo "=== Status for ${cluster} ==="

    if ! check_cluster_access "$cluster"; then
        return 1
    fi

    echo "Nodes:"
    kubectl --kubeconfig="$kubeconfig" get nodes

    echo ""
    echo "FluxCD Status:"
    if kubectl --kubeconfig="$kubeconfig" get namespace flux-system &>/dev/null; then
        flux get all --kubeconfig="$kubeconfig" 2>/dev/null || echo "FluxCD resources not found"
    else
        echo "FluxCD not installed"
    fi

    echo ""
    echo "Pods in macula namespace:"
    kubectl --kubeconfig="$kubeconfig" get pods -n macula 2>/dev/null || echo "No pods in macula namespace"

    echo ""
    echo "Services in macula namespace:"
    kubectl --kubeconfig="$kubeconfig" get svc -n macula 2>/dev/null || echo "No services in macula namespace"
}

usage() {
    echo "Usage: $0 <command> [cluster]"
    echo ""
    echo "Commands:"
    echo "  bootstrap <cluster|all>  - Bootstrap FluxCD on cluster(s)"
    echo "  reconcile <cluster|all>  - Trigger FluxCD reconciliation"
    echo "  status <cluster|all>     - Show cluster and FluxCD status"
    echo "  check                    - Check prerequisites and cluster access"
    echo ""
    echo "Clusters: beam00, beam01, beam02, beam03, all"
    echo ""
    echo "Environment variables:"
    echo "  GITHUB_TOKEN  - GitHub token for private repos (optional for public)"
    echo "  GITHUB_OWNER  - GitHub owner (default: macula-io)"
    echo "  GITHUB_REPO   - GitHub repo (default: macula-gitops)"
    echo "  GITHUB_BRANCH - Git branch (default: main)"
    echo ""
    echo "Examples:"
    echo "  $0 bootstrap beam00        # Bootstrap FluxCD on beam00"
    echo "  $0 bootstrap all           # Bootstrap FluxCD on all beam clusters"
    echo "  $0 reconcile all           # Trigger reconciliation on all clusters"
    echo "  $0 status all              # Show status of all clusters"
}

main() {
    local command="${1:-}"
    local target="${2:-}"

    if [[ -z "$command" ]]; then
        usage
        exit 1
    fi

    check_prerequisites

    local clusters=()
    case "$target" in
        beam00|beam01|beam02|beam03)
            clusters=("$target")
            ;;
        all)
            clusters=("beam00" "beam01" "beam02" "beam03")
            ;;
        "")
            if [[ "$command" != "check" ]]; then
                echo "ERROR: Cluster target required"
                usage
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Unknown cluster: $target"
            usage
            exit 1
            ;;
    esac

    case "$command" in
        bootstrap)
            for cluster in "${clusters[@]}"; do
                bootstrap_cluster "$cluster" || true
            done
            ;;
        reconcile)
            for cluster in "${clusters[@]}"; do
                reconcile_cluster "$cluster" || true
            done
            ;;
        status)
            for cluster in "${clusters[@]}"; do
                show_status "$cluster" || true
            done
            ;;
        check)
            echo "Checking all beam clusters..."
            for cluster in "beam00" "beam01" "beam02" "beam03"; do
                check_cluster_access "$cluster" || true
            done
            ;;
        *)
            echo "ERROR: Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
