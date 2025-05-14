#!/bin/bash

# Script to clean up and tear down the Open5GS Roaming Scenario

echo "Starting cleanup of Open5GS Roaming deployment..."

# --- Color definitions (optional, for better output) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}$1${NC}"
}

log_warning() {
  echo -e "${YELLOW}$1${NC}"
}

log_error() {
  echo -e "${RED}$1${NC}"
}

# --- Check for Minikube Tunnel ---
log_info "Checking if minikube tunnel is running..."
if ! pgrep -f "minikube tunnel" > /dev/null; then
    log_error "minikube tunnel is not running!"
    log_warning "This script requires 'minikube tunnel' to be active to correctly connect to the Kubernetes cluster and delete resources."
    read -p "Please run 'minikube tunnel' in a separate terminal and then press [Enter] to continue, or Ctrl+C to abort cleanup."
    # Re-check after user prompt
    if ! pgrep -f "minikube tunnel" > /dev/null; then
        log_error "minikube tunnel is still not detected. Aborting cleanup to prevent partial resource deletion."
        exit 1
    fi
    log_info "Minikube tunnel detected. Proceeding with cleanup..."
fi
echo ""

# --- Configuration (Namespaces and Helm Release Names) ---
# Ensure these match the names used in your deploy_roaming.sh script
HOME_NAMESPACE="home-network"
VISITED_NAMESPACE="visited-network"

HOME_OPEN5GS_RELEASE="home-open5gs"
HOME_OPEN5GS_NFS_RELEASE="home-open5gs-nfs"
VISITED_OPEN5GS_RELEASE="visited-open5gs"

HOME_SEPP_RELEASE="home-sepp"
VISITED_SEPP_RELEASE="visited-sepp"

PACKETRUSHER_RELEASE="packetrusher"

# --- 1. Delete Helm Releases ---
echo "1. Deleting Helm Releases"

# PacketRusher
echo "Deleting PacketRusher release: $PACKETRUSHER_RELEASE in namespace $VISITED_NAMESPACE..."
helm uninstall $PACKETRUSHER_RELEASE -n $VISITED_NAMESPACE 2>/dev/null || echo "PacketRusher release $PACKETRUSHER_RELEASE not found or already deleted."

# SEPPs
echo "Deleting Home SEPP release: $HOME_SEPP_RELEASE in namespace $HOME_NAMESPACE..."
helm uninstall $HOME_SEPP_RELEASE -n $HOME_NAMESPACE 2>/dev/null || echo "Home SEPP release $HOME_SEPP_RELEASE not found or already deleted."

echo "Deleting Visited SEPP release: $VISITED_SEPP_RELEASE in namespace $VISITED_NAMESPACE..."
helm uninstall $VISITED_SEPP_RELEASE -n $VISITED_NAMESPACE 2>/dev/null || echo "Visited SEPP release $VISITED_SEPP_RELEASE not found or already deleted."

# Visited Network Core
echo "Deleting Visited Open5GS release: $VISITED_OPEN5GS_RELEASE in namespace $VISITED_NAMESPACE..."
helm uninstall $VISITED_OPEN5GS_RELEASE -n $VISITED_NAMESPACE 2>/dev/null || echo "Visited Open5GS release $VISITED_OPEN5GS_RELEASE not found or already deleted."

# Home Network NFs
echo "Deleting Home Open5GS NFs release: $HOME_OPEN5GS_NFS_RELEASE in namespace $HOME_NAMESPACE..."
helm uninstall $HOME_OPEN5GS_NFS_RELEASE -n $HOME_NAMESPACE 2>/dev/null || echo "Home Open5GS NFs release $HOME_OPEN5GS_NFS_RELEASE not found or already deleted."

# Home Network MongoDB (if deployed as part of home-open5gs)
echo "Deleting Home Open5GS (MongoDB) release: $HOME_OPEN5GS_RELEASE in namespace $HOME_NAMESPACE..."
helm uninstall $HOME_OPEN5GS_RELEASE -n $HOME_NAMESPACE 2>/dev/null || echo "Home Open5GS (MongoDB) release $HOME_OPEN5GS_RELEASE not found or already deleted."
echo ""

# --- 2. Delete Kubernetes Resources (Jobs, PVCs if any) ---
# PVCs are usually managed by Helm, but jobs might persist if not cleaned up by Helm hooks.
echo "2. Deleting Kubernetes Resources"

# Delete add-subscriber job
echo "Deleting add-home-subscriber job in namespace $HOME_NAMESPACE..."
kubectl delete job add-home-subscriber -n $HOME_NAMESPACE --ignore-not-found=true

# Optionally, delete PersistentVolumeClaims if they are not automatically removed by Helm uninstall
# You might need to identify PVCs associated with MongoDB or other stateful sets
# echo "Listing PersistentVolumeClaims in $HOME_NAMESPACE..."
# kubectl get pvc -n $HOME_NAMESPACE
# echo "Listing PersistentVolumeClaims in $VISITED_NAMESPACE..."
# kubectl get pvc -n $VISITED_NAMESPACE
# echo "If any PVCs persist and need to be deleted, do so manually, e.g., kubectl delete pvc <pvc-name> -n <namespace>"
echo ""

# --- 3. Delete Namespaces ---
echo "3. Deleting Namespaces"

echo "Deleting namespace: $HOME_NAMESPACE..."
kubectl delete namespace $HOME_NAMESPACE --ignore-not-found=true

echo "Deleting namespace: $VISITED_NAMESPACE..."
kubectl delete namespace $VISITED_NAMESPACE --ignore-not-found=true
echo ""

# --- 4. Delete Locally Generated YAML files ---
echo "4. Deleting Locally Generated YAML files"

YAML_FILES=("add-subscriber-job.yaml" "home-sepp-values.yaml" "visited-sepp-values.yaml" "packetrusher-values.yaml")
for yaml_file in "${YAML_FILES[@]}"; do
  if [ -f "$yaml_file" ]; then
    echo "Deleting $yaml_file..."
    rm -f "$yaml_file"
  else
    echo "$yaml_file not found, skipping."
  fi
done
echo ""

echo "Cleanup Script Finished"
echo "Please verify that all resources have been terminated and namespaces are deleted."
echo "kubectl get pods -A"
echo "kubectl get ns"

# Helper function for printing section headers
echo() {
  echo "======================================================================"
  echo "$1"
  echo "======================================================================"
}

# End of Script 