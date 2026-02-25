#!/bin/bash

# Troubleshooting Script for Azure Document Intelligence Layout Helm Chart
# This script diagnoses and fixes common deployment issues

set -e

NAMESPACE="dev"
RELEASE="azure-layout-dev"

echo "=========================================="
echo "Helm Chart Troubleshooting & Diagnostics"
echo "=========================================="
echo ""

# Step 1: Check pod status
echo "1. Checking Pod Status..."
echo "---"
kubectl get pods -n $NAMESPACE
echo ""

# Step 2: Check PVC status
echo "2. Checking Persistent Volume Claims..."
echo "---"
kubectl get pvc -n $NAMESPACE
echo ""

# Step 3: Check for Pending pods
PENDING_PODS=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Pending")].metadata.name}')

if [ -n "$PENDING_PODS" ]; then
    echo "3. ISSUE FOUND: Pending Pods Detected"
    echo "---"
    for POD in $PENDING_PODS; do
        echo "Pod: $POD"
        echo "Scheduling issues:"
        kubectl describe pod -n $NAMESPACE $POD | grep -A 5 "Type.*Reason"
    done
    echo ""

    # Step 4: Check node labels
    echo "4. Checking Node Labels..."
    echo "---"
    kubectl get nodes --show-labels
    echo ""

    # Step 5: Solution - Remove node selector
    echo "5. FIXING: Removing node selector from dev environment..."
    echo "---"

    # Check if node selector is causing the issue
    NODE_SELECTOR=$(helm get values $RELEASE -n $NAMESPACE | grep -A 2 "nodeSelector:")
    if echo "$NODE_SELECTOR" | grep -q "environment"; then
        echo "Found environment node selector. Removing it..."

        # Update the values file
        sed -i '' 's/environment: dev//' /Users/madhu/Downloads/azure-form-recognizer-layout/azure-docintel-layout-helm/dev/dev-values.yaml

        echo "Upgrading Helm release..."
        helm upgrade $RELEASE /Users/madhu/Downloads/azure-form-recognizer-layout/azure-docintel-layout-helm/ \
          -f /Users/madhu/Downloads/azure-form-recognizer-layout/azure-docintel-layout-helm/dev/dev-values.yaml \
          --namespace $NAMESPACE

        echo "Waiting for pods to reschedule..."
        sleep 10

        echo ""
        echo "6. Checking Updated Pod Status..."
        echo "---"
        kubectl get pods -n $NAMESPACE
    fi
else
    echo "3. All pods are running or not pending!"
    echo "---"
fi

echo ""
echo "=========================================="
echo "Diagnostics Complete"
echo "=========================================="
echo ""

# Additional debugging info
echo "Additional Debugging Information:"
echo "---"
echo "Helm Release Info:"
helm list -n $NAMESPACE

echo ""
echo "Pod Details:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "Recent Events:"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10

echo ""
echo "Service Status:"
kubectl get svc -n $NAMESPACE

