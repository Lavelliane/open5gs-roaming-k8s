#!/bin/bash

# Script to deploy Open5GS Roaming Scenario
# Based on DEPLOYMENT_SUMMARY.md

# --- Color definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Colored echo functions ---
log_header() {
  echo -e "${BOLD}${BLUE}=====================================================================${NC}"
  echo -e "${BOLD}${BLUE}$1${NC}"
  echo -e "${BOLD}${BLUE}=====================================================================${NC}"
}

log_subheader() {
  echo -e "${BOLD}${CYAN}---------------------------------------------------------------------${NC}"
  echo -e "${BOLD}${CYAN}$1${NC}"
  echo -e "${BOLD}${CYAN}---------------------------------------------------------------------${NC}"
}

log_info() {
  echo -e "${GREEN}$1${NC}"
}

log_warning() {
  echo -e "${YELLOW}$1${NC}"
}

log_error() {
  echo -e "${RED}$1${NC}"
}

# Simple log function with no color
log() {
  echo -e "$1"
}

# --- Configuration Variables ---
# Please update these values based on your environment

# Minikube IP (or external IP if not using Minikube)
# Will be fetched dynamically.
MINIKUBE_IP=""

# NodePorts for SEPP N32 services.
# Will be fetched dynamically.
# HOME_SEPP_N32_NODEPORT="" # No longer needed for SEPP config
# VISITED_SEPP_N32_NODEPORT="" # No longer needed for SEPP config

# Helm chart versions and locations
OPEN5GS_CHART_VERSION="2.2.0"
OPEN5GS_CHART_REPO="oci://registry-1.docker.io/gradiant/open5gs"
LOCAL_CHARTS_PATH="./charts" # Path to your local 5g-charts checkout (for open5gs-sepp and packetrusher)

# MongoDB image tag
MONGO_IMAGE_TAG="4.4.15"

# --- Helper Functions ---

# Function to fetch Minikube IP
fetch_minikube_ip() {
  log_info "Fetching Minikube IP..."
  MINIKUBE_IP_FETCHED=$(minikube ip 2>/dev/null)
  if [ -z "$MINIKUBE_IP_FETCHED" ]; then
    log_error "Error: Could not automatically fetch Minikube IP."
    log_info "Please ensure Minikube is running and 'minikube ip' command works."
    read -p "Enter Minikube IP manually or press Ctrl+C to abort: " MINIKUBE_IP_FETCHED
    if [ -z "$MINIKUBE_IP_FETCHED" ]; then
        log_error "Minikube IP not provided. Exiting."
        exit 1
    fi
  fi
  MINIKUBE_IP="$MINIKUBE_IP_FETCHED"
  log_info "Using Minikube IP: $MINIKUBE_IP"
}

# Function to get NodePort with retries
get_node_port() {
    local namespace="$1"
    local service_name="$2"
    local port_val=""
    local retries=12 # Increased retries
    local delay=10  # Increased delay

    log_info "Attempting to fetch NodePort for $service_name in $namespace..."
    for i in $(seq 1 $retries); do
        port_val=$(kubectl get svc "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        if [[ -n "$port_val" && "$port_val" != "<no value>" && "$port_val" != "null" && "$port_val" -gt 0 ]]; then # Check if port_val is a number > 0
            log_info "Fetched NodePort for $service_name: $port_val"
            echo "$port_val"
            return 0
        fi
        log_warning "Attempt $i/$retries: NodePort not yet available for $service_name. Retrying in $delay seconds..."
        sleep $delay
    done
    log_error "Error: Could not fetch NodePort for $service_name in $namespace after $retries attempts."
    log_warning "Please ensure 'minikube tunnel' is running in a separate terminal and the service is correctly exposed."
    return 1
}

# Function to create add-subscriber-job.yaml
create_add_subscriber_job_yaml() {
cat << EOF > add-subscriber-job.yaml
# add-subscriber-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: add-home-subscriber
  namespace: home-network
spec:
  template:
    spec:
      containers:
      - name: dbctl
        image: docker.io/gradiant/open5gs-dbctl:0.10.3
        command: ["open5gs-dbctl", "add_ue_with_slice", "001011234567891", "7F176C500D47CF2090CB6D91F4A73479", "3D45770E83C7BBB6900F3653FDA6330F", "internet", "1", "000001"]
        env:
        - name: DB_URI
          value: "mongodb://home-open5gs-mongodb/open5gs"
      restartPolicy: Never
  backoffLimit: 4
EOF
log_info "Created add-subscriber-job.yaml"
}

# Function to create home-sepp-values.yaml
create_home_sepp_values_yaml() {
cat << EOF > home-sepp-values.yaml
customOpen5gsConfig:
  global:
    max:
      ue: 1024
  sepp:
    sbi:
      server:
        - address: 0.0.0.0
          port: 7777
      client:
        nrf:
          - uri: http://home-open5gs-nfs-nrf-sbi.home-network.svc.cluster.local:7777
    n32:
      server:
        - sender: home-sepp.home-network.svc.cluster.local
          scheme: http
          address: 0.0.0.0
          port: 7443
      n32f:
        scheme: http
        address: 0.0.0.0
      client:
        sepp:
          - receiver: visited-sepp.visited-network.svc.cluster.local
            uri: http://VISITED_SEPP_PLACEHOLDER
            plmn_id:
              mcc: "001"
              mnc: "01"
    default: {}
EOF
log_info "Created home-sepp-values.yaml with placeholder URIs"
}

# Function to create visited-sepp-values.yaml
create_visited_sepp_values_yaml() {
cat << EOF > visited-sepp-values.yaml
customOpen5gsConfig:
  global:
    max:
      ue: 1024
  sepp:
    sbi:
      server:
        - address: 0.0.0.0
          port: 7777
      client:
        nrf:
          - uri: http://visited-open5gs-nrf-sbi.visited-network.svc.cluster.local:7777
    n32:
      server:
        - sender: visited-sepp.visited-network.svc.cluster.local
          scheme: http
          address: 0.0.0.0
          port: 7443
      n32f:
        scheme: http
        address: 0.0.0.0
      client:
        sepp:
          - receiver: home-sepp.home-network.svc.cluster.local
            uri: http://HOME_SEPP_PLACEHOLDER
            plmn_id:
              mcc: "999"
              mnc: "70"
    default: {}
EOF
log_info "Created visited-sepp-values.yaml with placeholder URIs"
}

# Function to create packetrusher-values.yaml
create_packetrusher_values_yaml() {
cat << EOF > packetrusher-values.yaml
config:
    gnodeb:
      controlif:
        ip: '0.0.0.0'
        port: 38412
      dataif:
        ip: '0.0.0.0'
        port: 2152
      plmnlist:
        mcc: '999'
        mnc: '70'
        tac: '000001'
        gnbid: '000008'
      slicesupportlist:
        sst: '01'
        sd: '000001'

    ue:
      hplmn:
        mcc: '001'
        mnc: '01'
      msin: '1234567891'
      key: '7F176C500D47CF2090CB6D91F4A73479'
      opc: '3D45770E83C7BBB6900F3653FDA6330F'
      dnn: 'internet'
      snssai:
        sst: 01
        sd: '000001'
      amf: '8000'
      sqn: '00000000'
      protectionScheme: 0
      integrity:
        nia0: false
        nia1: false
        nia2: true
        nia3: false
      ciphering:
        nea0: true
        nea1: false
        nea2: true
        nea3: false

    amfif:
      - ip: 'v-amf.open5gs.svc.cluster.local'
        port: 38412
EOF
log_info "Created packetrusher-values.yaml"
}

# Function to update home-sepp-values.yaml with actual port
update_home_sepp_values_yaml() {
  log_info "Updating home-sepp-values.yaml with visited SEPP NodePort: $VISITED_SEPP_N32_NODEPORT"
  sed -i "s|http://VISITED_SEPP_PLACEHOLDER|http://${MINIKUBE_IP}:${VISITED_SEPP_N32_NODEPORT}|g" home-sepp-values.yaml
}

# Function to update visited-sepp-values.yaml with actual port
update_visited_sepp_values_yaml() {
  log_info "Updating visited-sepp-values.yaml with home SEPP NodePort: $HOME_SEPP_N32_NODEPORT"
  sed -i "s|http://HOME_SEPP_PLACEHOLDER|http://${MINIKUBE_IP}:${HOME_SEPP_N32_NODEPORT}|g" visited-sepp-values.yaml
}

# --- 1. Namespace Creation ---
log_header "1. Namespace Creation"
kubectl create namespace home-network
kubectl create namespace visited-network
log_info "Namespaces home-network and visited-network created."
echo ""

# Fetch Minikube IP early
fetch_minikube_ip
echo ""

# --- 2. Home Network Deployment ---
log_header "2. Home Network Deployment"

# 2.1 Deploy Home Network MongoDB
log_subheader "2.1 Deploy Home Network MongoDB"
helm install home-open5gs $OPEN5GS_CHART_REPO --version $OPEN5GS_CHART_VERSION \
  --namespace home-network \
  --set populate.enabled=false \
  --set hss.enabled=false \
  --set mme.enabled=false \
  --set pcrf.enabled=false \
  --set sgwc.enabled=false \
  --set sgwu.enabled=false \
  --set amf.enabled=false \
  --set smf.enabled=false \
  --set upf.enabled=false \
  --set ausf.enabled=false \
  --set bsf.enabled=false \
  --set nrf.enabled=false \
  --set nssf.enabled=false \
  --set pcf.enabled=false \
  --set scp.enabled=false \
  --set udm.enabled=false \
  --set udr.enabled=false \
  --set webui.enabled=false \
  --set mongodb.enabled=true \
  --set mongodb.image.tag=$MONGO_IMAGE_TAG \
  --set mongodb.livenessProbe.timeoutSeconds=30 \
  --set mongodb.readinessProbe.timeoutSeconds=30
log_info "Deployed Home Network MongoDB."
log_info "Waiting for MongoDB to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=home-open5gs,app.kubernetes.io/name=mongodb -n home-network --timeout=300s
echo ""

# 2.2 Add Home Subscriber
log_subheader "2.2 Add Home Subscriber"
create_add_subscriber_job_yaml
kubectl apply -f add-subscriber-job.yaml
log_info "Applied job to add home subscriber. Waiting for completion..."
kubectl wait --for=condition=complete job/add-home-subscriber -n home-network --timeout=120s
kubectl logs job/add-home-subscriber -n home-network --tail=10
log_info "Home subscriber job completed."
echo ""

# 2.3 Deploy Home Network NFs
log_subheader "2.3 Deploy Home Network NFs"
helm install home-open5gs-nfs $OPEN5GS_CHART_REPO --version $OPEN5GS_CHART_VERSION \
  --namespace home-network \
  --set dbURI=mongodb://home-open5gs-mongodb/open5gs \
  --set udr.extraEnvVars[0].name=DB_URI \
  --set udr.extraEnvVars[0].value=mongodb://home-open5gs-mongodb/open5gs \
  --set pcf.extraEnvVars[0].name=DB_URI \
  --set pcf.extraEnvVars[0].value=mongodb://home-open5gs-mongodb/open5gs \
  --set webui.extraEnvVars[0].name=DB_URI \
  --set webui.extraEnvVars[0].value=mongodb://home-open5gs-mongodb/open5gs \
  --set webui.populate.enabled=false \
  --set populate.enabled=false \
  --set hss.enabled=false \
  --set mme.enabled=false \
  --set pcrf.enabled=false \
  --set sgwc.enabled=false \
  --set sgwu.enabled=false \
  --set amf.enabled=true \
  --set smf.enabled=true \
  --set upf.enabled=true \
  --set ausf.enabled=true \
  --set bsf.enabled=true \
  --set nrf.enabled=true \
  --set nssf.enabled=true \
  --set pcf.enabled=true \
  --set scp.enabled=true \
  --set udm.enabled=true \
  --set udr.enabled=true \
  --set webui.enabled=true \
  --set mongodb.enabled=false \
  --set smf.config.pcrf.enabled=false
log_info "Deployed Home Network NFs."
echo ""

# --- 3. Visited Network Deployment ---
log_header "3. Visited Network Deployment"
# Deploy Visited Network Core
helm install visited-open5gs $OPEN5GS_CHART_REPO --version $OPEN5GS_CHART_VERSION \
  --namespace visited-network \
  --set mongodb.image.tag=$MONGO_IMAGE_TAG \
  --set smf.config.pcrf.enabled=false \
  --set mongodb.livenessProbe.timeoutSeconds=30 \
  --set mongodb.readinessProbe.timeoutSeconds=30 \
  --set udr.extraEnvVars[0].name=DB_URI \
  --set udr.extraEnvVars[0].value=mongodb://visited-open5gs-mongodb/open5gs \
  --set pcf.extraEnvVars[0].name=DB_URI \
  --set pcf.extraEnvVars[0].value=mongodb://visited-open5gs-mongodb/open5gs \
  --set webui.extraEnvVars[0].name=DB_URI \
  --set webui.extraEnvVars[0].value=mongodb://visited-open5gs-mongodb/open5gs \
  --set webui.populate.enabled=false \
  --set populate.enabled=false \
  --set hss.enabled=false \
  --set mme.enabled=false \
  --set pcrf.enabled=false \
  --set sgwc.enabled=false \
  --set sgwu.enabled=false \
  --set amf.enabled=true \
  --set smf.enabled=true \
  --set upf.enabled=true \
  --set ausf.enabled=true \
  --set bsf.enabled=true \
  --set nrf.enabled=true \
  --set nssf.enabled=true \
  --set pcf.enabled=true \
  --set scp.enabled=true \
  --set udm.enabled=true \
  --set udr.enabled=true \
  --set webui.enabled=true
  # Note: mongodb.enabled defaults to true and was used here
log_info "Deployed Visited Network Core."
echo ""

# --- 4. SEPP Configuration and Deployment ---
log_header "4. SEPP Configuration and Deployment"

# 4.1 Create SEPP Values Files
log_subheader "4.1 Create SEPP Values Files"
create_home_sepp_values_yaml
create_visited_sepp_values_yaml
echo ""

# 4.2 Initial SEPP Deployment (using local charts)
log_subheader "4.2 Initial SEPP Deployment"
log_info "Ensure your local charts are in: $LOCAL_CHARTS_PATH"
helm uninstall home-sepp -n home-network 2>/dev/null || true
helm install home-sepp ${LOCAL_CHARTS_PATH}/open5gs-sepp -f home-sepp-values.yaml --namespace home-network \
  --set containerPorts.sbi=80 \
  --set services.sbi.ports.sbi=80 \
  --set containerPorts.n32=80 \
  --set services.n32.ports.n32=80

helm uninstall visited-sepp -n visited-network 2>/dev/null || true
helm install visited-sepp ${LOCAL_CHARTS_PATH}/open5gs-sepp -f visited-sepp-values.yaml --namespace visited-network \
  --set containerPorts.sbi=80 \
  --set services.sbi.ports.sbi=80 \
  --set containerPorts.n32=80 \
  --set services.n32.ports.n32=80
log_info "Initial SEPP deployment completed."
log_info "Waiting for SEPPs to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=home-sepp -n home-network --timeout=180s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=visited-sepp -n visited-network --timeout=180s
echo ""

# 4.3 Expose SEPP N32 Interfaces
log_subheader "4.3 Expose SEPP N32 Interfaces"
log_info "Patching SEPP services to type: LoadBalancer."
log_info "IMPORTANT: Ensure 'minikube tunnel' is running in a separate terminal if using Minikube!"
kubectl patch service home-sepp-open5gs-sepp-n32 -n home-network -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch service visited-sepp-open5gs-sepp-n32 -n visited-network -p '{"spec": {"type": "LoadBalancer"}}'
log_info "Patched SEPP services. Waiting for external IP/NodePort assignment..."
log_info "This might take some time. If it hangs, ensure 'minikube tunnel' is active and services are exposing correctly."

# Dynamically fetch NodePorts
HOME_SEPP_N32_NODEPORT_FETCHED=$(get_node_port "home-network" "home-sepp-open5gs-sepp-n32")
if [ $? -ne 0 ]; then
    read -p "Enter Home SEPP N32 NodePort manually or press Ctrl+C to abort: " HOME_SEPP_N32_NODEPORT_FETCHED
    if [ -z "$HOME_SEPP_N32_NODEPORT_FETCHED" ]; then log_error "Home SEPP NodePort not provided. Exiting."; exit 1; fi
fi
HOME_SEPP_N32_NODEPORT="$HOME_SEPP_N32_NODEPORT_FETCHED"

VISITED_SEPP_N32_NODEPORT_FETCHED=$(get_node_port "visited-network" "visited-sepp-open5gs-sepp-n32")
if [ $? -ne 0 ]; then
    read -p "Enter Visited SEPP N32 NodePort manually or press Ctrl+C to abort: " VISITED_SEPP_N32_NODEPORT_FETCHED
    if [ -z "$VISITED_SEPP_N32_NODEPORT_FETCHED" ]; then log_error "Visited SEPP NodePort not provided. Exiting."; exit 1; fi
fi
VISITED_SEPP_N32_NODEPORT="$VISITED_SEPP_N32_NODEPORT_FETCHED"

echo ""
log_info "--- Verification ---"
log_info "Minikube IP (if fetched for other purposes): $MINIKUBE_IP"
log_info "Using Home SEPP N32 NodePort: $HOME_SEPP_N32_NODEPORT"
log_info "Using Visited SEPP N32 NodePort: $VISITED_SEPP_N32_NODEPORT"
log_info "SEPP communication will use Minikube IP and NodePorts with ports 7777 for SBI and 7443 for N32."
log_info "--------------------"
read -p "Press [Enter] to continue with these SEPP configurations, or Ctrl+C to abort."
echo ""

# 4.4 Reconfigure SEPPs for External Communication
log_subheader "4.4 Reconfigure SEPPs with External URIs"
update_home_sepp_values_yaml
update_visited_sepp_values_yaml

helm uninstall home-sepp -n home-network 2>/dev/null || true # Ensure uninstall happens before install
helm install home-sepp ${LOCAL_CHARTS_PATH}/open5gs-sepp -f home-sepp-values.yaml --namespace home-network \
  --set containerPorts.sbi=7777 \
  --set services.sbi.ports.sbi=7777 \
  --set containerPorts.n32=7443 \
  --set services.n32.ports.n32=7443

helm uninstall visited-sepp -n visited-network 2>/dev/null || true # Ensure uninstall happens
helm install visited-sepp ${LOCAL_CHARTS_PATH}/open5gs-sepp -f visited-sepp-values.yaml --namespace visited-network \
  --set containerPorts.sbi=7777 \
  --set services.sbi.ports.sbi=7777 \
  --set containerPorts.n32=7443 \
  --set services.n32.ports.n32=7443
log_info "Reinstalled SEPPs with updated values files for external communication."
log_info "Waiting for SEPPs to be ready after reconfiguration..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=home-sepp -n home-network --timeout=180s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=visited-sepp -n visited-network --timeout=180s
echo ""

# --- 5. Deploy PacketRusher ---
log_header "5. Deploy PacketRusher"
create_packetrusher_values_yaml
helm install packetrusher ${LOCAL_CHARTS_PATH}/packetrusher -f packetrusher-values.yaml --namespace visited-network
log_info "Deployed PacketRusher."
echo ""

log_header "Deployment Script Finished"
log_info "Check pod statuses in home-network and visited-network namespaces."
log_info "kubectl get pods -n home-network"
log_info "kubectl get pods -n visited-network"

# --- Main Execution ---
# (Moved helper functions to the top for clarity, main execution flows from top to bottom)

# Initial check for local charts path
if [ ! -d "${LOCAL_CHARTS_PATH}/open5gs-sepp" ] || [ ! -d "${LOCAL_CHARTS_PATH}/packetrusher" ]; then
  log_error "ERROR: Local charts path '${LOCAL_CHARTS_PATH}' does not seem to contain open5gs-sepp or packetrusher."
  log_info "Please ensure LOCAL_CHARTS_PATH is set correctly and contains the chart directories."
  exit 1
fi

log_info "Starting Open5GS Roaming Deployment..."
log_info "Ensure you have 'minikube tunnel' running if using Minikube."
read -p "Press [Enter] to begin deployment..."

# Call sections (This is illustrative; script executes sequentially)
# 1. Namespace Creation (already called)
# 2. Home Network Deployment (already called)
# 3. Visited Network Deployment (already called)
# 4. SEPP Configuration and Deployment (already called)
# 5. Deploy PacketRusher (already called)

# End of Script 