# Azure Form Recognizer Layout (On-Prem Helm Chart)

This repository packages a production-ready Helm chart for the Microsoft Azure AI Document Intelligence Layout container. The chart is designed for on-prem Kubernetes clusters and uses `.yaml.gotmpl` values for environment-specific overrides.

## What is included
- Helm chart in `form-recognizer/` with Deployment, Service, PVCs, Secret, ConfigMap, helpers, and notes.
- Base configuration in `form-recognizer/base-config.yaml.gotmpl`.
- Environment overrides in `form-recognizer/default`, `form-recognizer/dev`, `form-recognizer/uat`, and `form-recognizer/prod`.
- Maven assembly to package the chart into a tar.gz for Artifactory.

## Prerequisites
- Kubernetes v1.25+
- Helm v3+
- A default StorageClass in the cluster, or set `persistence.*.storageClassName` in the values
- Valid Azure Form Recognizer credentials

## Configure environment placeholders
The base `.gotmpl` uses environment placeholders for secrets. Set these in your shell or CI environment before rendering:
- `FORM_RECOGNIZER_KEY`
- `FORM_RECOGNIZER_ENDPOINT_URI`

Example:
```zsh
export FORM_RECOGNIZER_KEY="<your-key>"
export FORM_RECOGNIZER_ENDPOINT_URI="https://<your-endpoint>"
```

## Proxy configuration (environment-specific)
Add proxy settings in your environment override values file:

```yaml
proxyEnv:
  HTTP_PROXY: "http://proxy-host:8080"
  HTTPS_PROXY: "http://proxy-host:8080"
  NO_PROXY: "localhost,127.0.0.1,.cluster.local"
```

## Custom CA certificate (environment-specific)
If your Azure endpoint is behind a proxy or uses a private CA, create a ConfigMap with the CA bundle and mount it into the pod:

```zsh
kubectl -n form-recognizer-dev create configmap fr-ca-bundle \
  --from-file=ca.crt=/path/to/your/ca.crt
```

Add this to your environment override values file:

```yaml
caCertConfigMap:
  name: "fr-ca-bundle"
  mountPath: /etc/ssl/certs/custom
  items:
    - key: ca.crt
      path: ca.crt
```

Then configure the container to trust the mounted CA (if required by your runtime) via `SSL_CERT_DIR` or `SSL_CERT_FILE`:

```yaml
proxyEnv:
  SSL_CERT_DIR: "/etc/ssl/certs/custom"
  # or
  # SSL_CERT_FILE: "/etc/ssl/certs/custom/ca.crt"
```

## Namespaces per environment
Recommended namespace convention to isolate environments:
- dev: `form-recognizer-dev`
- uat: `form-recognizer-uat`
- prod: `form-recognizer-prod`

Use the same release name (e.g., `layout`) in each namespace for consistency.

## Helm install/upgrade
Install (base + dev overrides):
```zsh
helm install layout ./form-recognizer \
  -f form-recognizer/base-config.yaml.gotmpl \
  -f form-recognizer/dev/values.yaml.gotmpl \
  -n form-recognizer --create-namespace
```

Upgrade (base + prod overrides):
```zsh
helm upgrade layout ./form-recognizer \
  -f form-recognizer/base-config.yaml.gotmpl \
  -f form-recognizer/prod/values.yaml.gotmpl \
  -n form-recognizer
```

Deploy a specific environment (example: uat):
```zsh
helm upgrade --install layout ./form-recognizer \
  -f form-recognizer/base-config.yaml.gotmpl \
  -f form-recognizer/uat/values.yaml.gotmpl \
  -n form-recognizer --create-namespace
```

## Packaging the Helm chart tar.gz
The Maven build creates a tar.gz that includes `form-recognizer/` and `README.md`.

Build locally:
```zsh
./mvnw -DskipTests package
```

The tar.gz will be generated under `target/` as:
- `azure-form-recognizer-layout-<version>.tar.gz`

## Upload to Artifactory
The `pom.xml` includes placeholders for Artifactory URLs. Update these before deploying:
- `artifactory.release.url`
- `artifactory.snapshot.url`

Then deploy:
```zsh
./mvnw -DskipTests deploy
```

## Notes
- PVCs are enabled by default. If your on-prem cluster requires a specific StorageClass, set it in `base-config.yaml.gotmpl` or environment overrides.
- If you need RWX volumes for multi-replica access, set `persistence.*.accessModes` to `ReadWriteMany`.
