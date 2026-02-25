# Azure AI Document Intelligence Layout - Helm Chart

This repository provides a production-ready Helm chart for deploying the **Microsoft Azure AI Document Intelligence Layout 4.0 container** to Kubernetes clusters (on-premise or cloud).

## 📋 Table of Contents
- [Overview](#overview)
- [What's Included](#whats-included)
- [Prerequisites](#prerequisites)
- [Platform Compatibility](#platform-compatibility)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)
- [Build & Package](#build--package)

---

## Overview

The Azure AI Document Intelligence Layout service analyzes and extracts text, tables, and structure from documents. This Helm chart packages the container for deployment with:
- Environment-specific configurations (dev/uat/prod)
- Persistent storage for shared data and outputs
- Configurable resources, replicas, and probes
- Support for proxy and custom CA certificates
- Production-ready security and best practices

## What's Included

```
azure-docintel-layout-helm/
├── Chart.yaml                    # Chart metadata
├── values.yaml                   # Default values
├── templates/                    # Kubernetes manifests
│   ├── deployment.yaml          # Pod deployment
│   ├── service.yaml             # Service configuration
│   ├── pvc.yaml                 # Persistent volume claims
│   ├── secret.yaml              # Secrets for API credentials
│   ├── configmap.yaml           # Optional configuration
│   └── _helpers.tpl             # Template helpers
├── default/default-values.yaml  # Default environment
├── dev/dev-values.yaml          # Development overrides
├── uat/uat-values.yaml          # UAT overrides
└── prod/prod-values.yaml        # Production overrides
```

**Also included:**
- Maven `pom.xml` for packaging as tar.gz
- Kubernetes manifest files in `manifests/` for reference
- Deployment scripts and documentation

## Prerequisites

- **Kubernetes:** v1.25+ (tested with minikube, AKS, EKS, GKE)
- **Helm:** v3.0+
- **kubectl:** Latest stable version
- **StorageClass:** Default or specify in values
- **Docker:** For local testing (optional)
- **Azure Credentials:** API key and billing endpoint

### Install Helm (if not installed)

**macOS:**
```bash
brew install helm
```

**Linux:**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Verify installation:**
```bash
helm version
```

## Platform Compatibility

⚠️ **IMPORTANT:** The Azure Document Intelligence Layout 4.0 image **ONLY supports `linux/amd64`** platform.

### Supported:
- ✅ Intel/AMD x86_64 processors
- ✅ Cloud Kubernetes (AKS, EKS, GKE) - typically amd64 by default
- ✅ On-premise x86_64 clusters

### Not Supported:
- ❌ ARM64 (Apple Silicon M1/M2/M3/M4)
- ❌ Windows containers

### For Apple Silicon Macs (Local Development)

**Pull image with platform flag:**
```bash
docker pull --platform=linux/amd64 \
  mcr.microsoft.com/azure-cognitive-services/form-recognizer/layout-4.0
```

**Configure minikube:**
```bash
minikube start --driver=docker
```

**Or enable Rosetta in Docker Desktop:**
1. Open Docker Desktop → Settings
2. Features in development → Enable Rosetta
3. Restart Docker Desktop

---

## Quick Start

### 1. Start Kubernetes Cluster

**For minikube:**
```bash
minikube start
```

**Verify:**
```bash
kubectl cluster-info
kubectl get nodes
```

### 2. Configure Secrets

Create a secret with your Azure credentials:

```bash
kubectl create namespace dev

kubectl create secret generic azure-layout-secret \
  --from-literal=apikey='<YOUR_API_KEY>' \
  --from-literal=billing='<YOUR_BILLING_ENDPOINT>' \
  --namespace dev
```

### 3. Deploy with Helm

**Development environment:**
```bash
helm install azure-layout-dev azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml \
  --namespace dev \
  --create-namespace
```

### 4. Verify Deployment

```bash
# Check pods
kubectl get pods -n dev

# Check services
kubectl get svc -n dev

# View logs
kubectl logs -n dev -l app.kubernetes.io/name=azure-docintel-layout

# Port forward to access service
kubectl port-forward -n dev svc/azure-layout-dev-azure-docintel-layout 5000:5000
```

Access the service at: `http://localhost:5000`

---

## Configuration


### Environment-Specific Values

Each environment has its own values file with appropriate resource allocation:

| Environment | File | Replicas | CPU | Memory | Storage |
|-------------|------|----------|-----|--------|---------|
| **Default** | `default/default-values.yaml` | 1 | - | - | 10Gi |
| **Dev** | `dev/dev-values.yaml` | 1 | 250m-1 | 1-2Gi | 5Gi |
| **UAT** | `uat/uat-values.yaml` | 1 | 500m-2 | 2-4Gi | 10Gi |
| **Prod** | `prod/prod-values.yaml` | 2 | 1-4 | 4-8Gi | 20Gi |

### Key Configuration Options

**Image:**
```yaml
image:
  repository: mcr.microsoft.com/azure-cognitive-services/form-recognizer/layout-4.0
  tag: latest
  pullPolicy: IfNotPresent
```

**Persistence:**
```yaml
persistence:
  shared:
    enabled: true
    size: 10Gi
    storageClassName: "standard"  # or your storage class
  output:
    enabled: true
    size: 10Gi
    storageClassName: "standard"
```

**Resources:**
```yaml
resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 2
    memory: 4Gi
```

**Proxy (Optional):**
```yaml
proxyEnv:
  HTTP_PROXY: "http://proxy.example.com:8080"
  HTTPS_PROXY: "http://proxy.example.com:8080"
  NO_PROXY: "localhost,127.0.0.1,.svc,.cluster.local"
```

**CA Certificates (Optional):**
```yaml
caCertConfigMap:
  name: "custom-ca-certs"
  mountPath: /etc/ssl/certs/custom
  items:
    - key: ca-bundle.crt
      path: ca-bundle.crt
```

### Secrets Configuration

The chart supports **two modes** for handling secrets:

#### **Option 1: Use Pre-existing Kubernetes Secret (Recommended)**

If you already have a secret in your Kubernetes cluster, reference it:

**Your pre-existing secret (already created):**
```bash
kubectl get secret azure-layout-secret -n dev
```

**In your values file (already configured in dev/uat/prod-values.yaml):**
```yaml
secret:
  create: false  # Don't create a new secret
  externalSecretName: "azure-layout-secret"  # Reference your existing secret

secretEnv:
  apikey: ""  # Will be fetched from external secret
  billing: ""  # Will be fetched from external secret
```

**Deploy with Helm (no secret creation needed):**
```bash
helm install azure-layout-dev azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml \
  --namespace dev
```

#### **Option 2: Helm Creates the Secret**

If you don't have a pre-existing secret, Helm can create one:

**In your values file:**
```yaml
secret:
  create: true  # Helm will create the secret
  nameOverride: ""

secretEnv:
  apikey: "your-api-key"
  billing: "https://your-endpoint.cognitiveservices.azure.com/"
```

**Deploy with Helm (secret will be created):**
```bash
helm install azure-layout-dev azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml \
  --namespace dev
```

---

### How to Create Pre-existing Secret (One Time Setup)

Create the secret once in your namespace:

```bash
kubectl create namespace dev

kubectl create secret generic azure-layout-secret \
  --from-literal=apikey='<YOUR_API_KEY>' \
  --from-literal=billing='<YOUR_BILLING_ENDPOINT>' \
  --namespace dev
```

**Verify the secret:**
```bash
kubectl get secret azure-layout-secret -n dev
kubectl describe secret azure-layout-secret -n dev
```

**Then deploy Helm with the existing secret (no re-creation):**
```bash
helm install azure-layout-dev azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml \
  --namespace dev
```

---

### 3. Deploy with Helm (Using Pre-existing Secret)

**Development environment:**
```bash
helm install azure-layout-dev azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml \
  --namespace dev
```

The chart will reference the pre-existing `azure-layout-secret` without creating a new one.

### 4. Verify Deployment

```bash

### Deploy to UAT

```bash
helm install azure-layout-uat azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/uat/uat-values.yaml \
  --namespace uat \
  --create-namespace
```

### Deploy to Production

```bash
helm install azure-layout-prod azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/prod/prod-values.yaml \
  --namespace prod \
  --create-namespace
```

### Upgrade Existing Deployment

```bash
helm upgrade azure-layout-dev azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml \
  --namespace dev
```

### Install or Upgrade (Idempotent)

```bash
helm upgrade --install azure-layout-dev azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml \
  --namespace dev \
  --create-namespace
```

### Uninstall

```bash
helm uninstall azure-layout-dev --namespace dev
```

### Dry Run / Template Test

Before deploying, test the rendered manifests:

```bash
helm template test azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml \
  --namespace dev
```

### Lint the Chart

```bash
helm lint azure-docintel-layout-helm/ \
  -f azure-docintel-layout-helm/dev/dev-values.yaml
```

---

## Troubleshooting

### Pod Status: "ImagePullBackOff"

**Check events:**
```bash
kubectl describe pod -n dev <pod-name>
```

**Solutions:**

1. **Platform mismatch (ARM64 vs amd64):**
   ```bash
   # Pre-load image for minikube
   docker pull --platform=linux/amd64 mcr.microsoft.com/azure-cognitive-services/form-recognizer/layout-4.0
   minikube image load mcr.microsoft.com/azure-cognitive-services/form-recognizer/layout-4.0:latest
   ```

2. **Verify node architecture:**
   ```bash
   kubectl get nodes -o wide
   ```

### Pod Status: "Pending"

**Check PVC status:**
```bash
kubectl get pvc -n dev
```

**Check events:**
```bash
kubectl get events -n dev --sort-by=.metadata.creationTimestamp
```

**Common causes:**
- PVC not bound (no storage class or insufficient storage)
- Insufficient resources on nodes
- Node selector mismatch

**Solution - check storage class:**
```bash
kubectl get storageclass
```

### Pod Running but Not Ready

**Check readiness probe:**
```bash
kubectl describe pod -n dev <pod-name>
```

**Check logs:**
```bash
kubectl logs -n dev <pod-name>
```

**Common causes:**
- Missing or invalid API credentials
- Service not starting properly
- Readiness probe failing

### Connection Issues

**Verify service:**
```bash
kubectl get svc -n dev
```

**Port forward for testing:**
```bash
kubectl port-forward -n dev svc/azure-layout-dev-azure-docintel-layout 5000:5000
```

**Test endpoint:**
```bash
curl http://localhost:5000
```

### View All Resources

```bash
kubectl get all -n dev
```

### Check Helm Release

```bash
# List releases
helm list -n dev

# Get release values
helm get values azure-layout-dev -n dev

# Get rendered manifest
helm get manifest azure-layout-dev -n dev
```

---

## Build & Package

### Build Helm Chart as tar.gz

The project includes a Maven configuration to package the Helm chart:

```bash
mvn clean package -DskipTests
```

**Output:**
- `target/azure-form-recognizer-layout-0.0.1-SNAPSHOT.tar.gz`

**What's included in the tar:**
- Helm chart (`azure-docintel-layout-helm/`)
- Chart metadata and templates
- Base `values.yaml`
- README.md

**What's excluded:**
- Environment folders (`dev/`, `uat/`, `prod/`)
- Manifest files
- Test files

### Extract and Deploy from tar.gz

```bash
# Extract
tar -xzf target/azure-form-recognizer-layout-0.0.1-SNAPSHOT.tar.gz
cd azure-form-recognizer-layout-0.0.1-SNAPSHOT

# Deploy with external environment values
helm install azure-layout azure-docintel-layout-helm/ \
  -f /path/to/external/dev-values.yaml \
  --namespace dev \
  --create-namespace
```

### Exclude from Jenkins Assembly

If using Jenkins to build, exclude manifest files in `assembly.xml`:

```xml
<fileSet>
  <directory>${project.basedir}</directory>
  <outputDirectory>/</outputDirectory>
  <excludes>
    <exclude>manifests/**</exclude>
    <exclude>dev/**</exclude>
    <exclude>uat/**</exclude>
    <exclude>prod/**</exclude>
  </excludes>
</fileSet>
```

---

## Advanced Configuration

### Custom Storage Class

```yaml
persistence:
  shared:
    storageClassName: "fast-ssd"  # Use your storage class
  output:
    storageClassName: "fast-ssd"
```

### Node Affinity

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-type
          operator: In
          values:
          - compute-optimized
```

### Pod Anti-Affinity (Production)

Already configured in `prod/prod-values.yaml`:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - azure-docintel-layout
          topologyKey: kubernetes.io/hostname
```

### Horizontal Pod Autoscaler (HPA)

```yaml
# Not included in chart, apply separately
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: azure-layout-hpa
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: azure-layout-prod-azure-docintel-layout
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

## Useful Commands

### Helm Commands

```bash
# List all releases across all namespaces
helm list -A

# Get chart info
helm show chart azure-docintel-layout-helm/

# Get default values
helm show values azure-docintel-layout-helm/

# Rollback to previous version
helm rollback azure-layout-dev 1 -n dev

# View release history
helm history azure-layout-dev -n dev
```

### Kubectl Commands

```bash
# Get pod logs (all containers)
kubectl logs -n dev <pod-name> --all-containers=true

# Follow logs
kubectl logs -n dev <pod-name> -f

# Execute command in pod
kubectl exec -n dev <pod-name> -- ls -la /share

# Get resource usage
kubectl top pods -n dev
kubectl top nodes

# Describe all resources
kubectl describe all -n dev

# Get persistent volume claims
kubectl get pvc -n dev

# Get secrets
kubectl get secrets -n dev
```

---

## Support & Documentation

- **Azure AI Document Intelligence:** [Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-services/document-intelligence/)
- **Container Documentation:** [Cognitive Services Containers](https://learn.microsoft.com/en-us/azure/cognitive-services/cognitive-services-container-support)
- **Helm Documentation:** [helm.sh](https://helm.sh/docs/)
- **Kubernetes Documentation:** [kubernetes.io](https://kubernetes.io/docs/)

---

## License

This Helm chart is provided as-is. The Azure AI Document Intelligence container is subject to Microsoft's licensing terms.

---

## Contributing

For issues, improvements, or questions about this Helm chart, please contact your DevOps team or repository maintainers.

