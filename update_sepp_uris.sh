#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error when substituting.
set -o pipefail # Causes a pipeline to return the exit status of the last command in the pipe that returned a non-zero return value.

echo "🔍 Fetching Minikube IP..."
MINIKUBE_IP=$(minikube ip)
if [ -z "$MINIKUBE_IP" ]; then
    echo "❌ Error: Failed to get Minikube IP. Is Minikube running and accessible?"
    exit 1
fi
echo "✅ Minikube IP: $MINIKUBE_IP"

echo "🔍 Fetching Home SEPP N32 NodePort (service: home-sepp-open5gs-sepp-n32 on port 7443)..."
HOME_SEPP_NODEPORT=$(kubectl get svc home-sepp-open5gs-sepp-n32 -n home-network -o jsonpath='{.spec.ports[?(@.port==7443)].nodePort}')
if [ -z "$HOME_SEPP_NODEPORT" ]; then
    echo "❌ Error: Failed to get Home SEPP NodePort."
    echo "   Ensure the service 'home-sepp-open5gs-sepp-n32' exists in namespace 'home-network',"
    echo "   is of type LoadBalancer, and 'minikube tunnel' is active and has assigned a NodePort."
    echo "   Current service details:"
    kubectl get svc home-sepp-open5gs-sepp-n32 -n home-network -o yaml
    exit 1
fi
echo "✅ Home SEPP N32 NodePort: $HOME_SEPP_NODEPORT"

echo "🔍 Fetching Visited SEPP N32 NodePort (service: visited-sepp-open5gs-sepp-n32 on port 7443)..."
VISITED_SEPP_NODEPORT=$(kubectl get svc visited-sepp-open5gs-sepp-n32 -n visited-network -o jsonpath='{.spec.ports[?(@.port==7443)].nodePort}')
if [ -z "$VISITED_SEPP_NODEPORT" ]; then
    echo "❌ Error: Failed to get Visited SEPP NodePort."
    echo "   Ensure the service 'visited-sepp-open5gs-sepp-n32' exists in namespace 'visited-network',"
    echo "   is of type LoadBalancer, and 'minikube tunnel' is active and has assigned a NodePort."
    echo "   Current service details:"
    kubectl get svc visited-sepp-open5gs-sepp-n32 -n visited-network -o yaml
    exit 1
fi
echo "✅ Visited SEPP N32 NodePort: $VISITED_SEPP_NODEPORT"

# Construct the URIs
HOME_SEPP_EXTERNAL_URI="http://${MINIKUBE_IP}:${HOME_SEPP_NODEPORT}"
VISITED_SEPP_EXTERNAL_URI="http://${MINIKUBE_IP}:${VISITED_SEPP_NODEPORT}"

echo "ℹ️  Home SEPP external URI will be: $HOME_SEPP_EXTERNAL_URI"
echo "ℹ️  Visited SEPP external URI will be: $VISITED_SEPP_EXTERNAL_URI"

# Define placeholder
PLACEHOLDER_URI="http://<INITIAL_INTERNAL_URI_PLACEHOLDER>"

# Update home-sepp-values.yaml
HOME_SEPP_VALUES_FILE="home-sepp-values.yaml"
echo "🔄 Updating $HOME_SEPP_VALUES_FILE to point to Visited SEPP URI: $VISITED_SEPP_EXTERNAL_URI"
if [ ! -f "$HOME_SEPP_VALUES_FILE" ]; then
    echo "❌ Error: $HOME_SEPP_VALUES_FILE not found in current directory!"
    exit 1
fi
sed -i.bak "s|uri: ${PLACEHOLDER_URI}|uri: ${VISITED_SEPP_EXTERNAL_URI}|g" "$HOME_SEPP_VALUES_FILE"
echo "✅ $HOME_SEPP_VALUES_FILE updated. Original saved as $HOME_SEPP_VALUES_FILE.bak"
echo "Verifying update in $HOME_SEPP_VALUES_FILE:"
if grep -q "uri: ${VISITED_SEPP_EXTERNAL_URI}" "$HOME_SEPP_VALUES_FILE"; then
    echo "✔️ Verification successful for $HOME_SEPP_VALUES_FILE."
else
    echo "⚠️ Verification failed for $HOME_SEPP_VALUES_FILE. Please check the file manually."
fi

# Update visited-sepp-values.yaml
VISITED_SEPP_VALUES_FILE="visited-sepp-values.yaml"
echo "🔄 Updating $VISITED_SEPP_VALUES_FILE to point to Home SEPP URI: $HOME_SEPP_EXTERNAL_URI"
if [ ! -f "$VISITED_SEPP_VALUES_FILE" ]; then
    echo "❌ Error: $VISITED_SEPP_VALUES_FILE not found in current directory!"
    exit 1
fi
sed -i.bak "s|uri: ${PLACEHOLDER_URI}|uri: ${HOME_SEPP_EXTERNAL_URI}|g" "$VISITED_SEPP_VALUES_FILE"
echo "✅ $VISITED_SEPP_VALUES_FILE updated. Original saved as $VISITED_SEPP_VALUES_FILE.bak"
echo "Verifying update in $VISITED_SEPP_VALUES_FILE:"
if grep -q "uri: ${HOME_SEPP_EXTERNAL_URI}" "$VISITED_SEPP_VALUES_FILE"; then
    echo "✔️ Verification successful for $VISITED_SEPP_VALUES_FILE."
else
    echo "⚠️ Verification failed for $VISITED_SEPP_VALUES_FILE. Please check the file manually."
fi

echo "🎉 Script finished successfully!"
echo "You can now proceed with Step 9: Reinstall SEPPs with updated values."
echo "Example commands:"
echo "helm uninstall home-sepp -n home-network && helm install home-sepp ./charts/open5gs-sepp -f home-sepp-values.yaml --namespace home-network"
echo "helm uninstall visited-sepp -n visited-network && helm install visited-sepp ./charts/open5gs-sepp -f visited-sepp-values.yaml --namespace visited-network" 