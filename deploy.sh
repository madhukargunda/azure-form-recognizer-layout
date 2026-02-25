#!/bin/bash

###############################################################################
# Azure Document Intelligence Layout Helm Deployment Script
# Usage: ./deploy.sh <environment> <namespace> [release-name]
# Example: ./deploy.sh dev docintel-layout-dev layout
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/azure-docintel-layout-helm"

# Default values
RELEASE_NAME="${3:-layout}"
DRY_RUN="${DRY_RUN:-false}"

###############################################################################
# Functions
###############################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 <environment> <namespace> [release-name]

Arguments:
  environment   Environment to deploy (dev, uat, prod)
  namespace     Kubernetes namespace
  release-name  Helm release name (default: layout)

Environment Variables:
  FORM_RECOGNIZER_KEY          Azure Form Recognizer API key (required)
  FORM_RECOGNIZER_ENDPOINT_URI Azure Form Recognizer endpoint (required)
  DRY_RUN                      Set to 'true' to skip actual deployment (default: false)
  VALUES_FILE_PATH             Custom path to environment values file (optional)
  SKIP_CONFIRM                 Set to 'true' to skip confirmation prompts (default: false)

Examples:
  # Deploy to dev
  export FORM_RECOGNIZER_KEY="your-key"
  export FORM_RECOGNIZER_ENDPOINT_URI="https://your-endpoint"
  $0 dev docintel-layout-dev

  # Deploy to prod with custom release name
  $0 prod docintel-layout-prod layout-prod

  # Dry run (template only, no deployment)
  DRY_RUN=true $0 dev docintel-layout-dev

  # Skip confirmation prompts
  SKIP_CONFIRM=true $0 dev docintel-layout-dev

EOF
    exit 1
}

check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install Helm 3+"
        exit 1
    fi

    local helm_version
    helm_version=$(helm version --short 2>/dev/null || echo "unknown")
    log_info "Helm version: ${helm_version}"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi

    local kubectl_version
    kubectl_version=$(kubectl version --client --short 2>/dev/null || echo "unknown")
    log_info "kubectl version: ${kubectl_version}"

    # Check chart directory
    if [ ! -d "${CHART_DIR}" ]; then
        log_error "Helm chart directory not found: ${CHART_DIR}"
        exit 1
    fi

    # Check Chart.yaml
    if [ ! -f "${CHART_DIR}/Chart.yaml" ]; then
        log_error "Chart.yaml not found in: ${CHART_DIR}"
        exit 1
    fi

    # Check required environment variables
    if [ -z "${FORM_RECOGNIZER_KEY}" ]; then
        log_error "FORM_RECOGNIZER_KEY environment variable is required"
        log_info "Set it with: export FORM_RECOGNIZER_KEY=\"your-key\""
        exit 1
    fi

    if [ -z "${FORM_RECOGNIZER_ENDPOINT_URI}" ]; then
        log_error "FORM_RECOGNIZER_ENDPOINT_URI environment variable is required"
        log_info "Set it with: export FORM_RECOGNIZER_ENDPOINT_URI=\"https://your-endpoint\""
        exit 1
    fi

    log_info "✓ Prerequisites check passed"
    echo ""
}

check_kubernetes_context() {
    log_step "Checking Kubernetes connection..."

    local current_context
    current_context=$(kubectl config current-context 2>/dev/null || echo "none")

    if [ "${current_context}" = "none" ]; then
        log_error "No Kubernetes context found. Please configure kubectl."
        exit 1
    fi

    log_info "Current Kubernetes context: ${current_context}"

    # Test connection
    if kubectl cluster-info &> /dev/null; then
        log_info "✓ Kubernetes cluster is reachable"
    else
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    if [ "${SKIP_CONFIRM}" != "true" ]; then
        echo ""
        log_warn "You are about to deploy to context: ${current_context}"
        read -p "Continue with this context? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
            log_error "Deployment cancelled by user"
            exit 1
        fi
    fi
    echo ""
}

helm_lint_chart() {
    log_step "Running Helm lint..."

    if helm lint "${CHART_DIR}" 2>&1 | tee /tmp/helm-lint.log; then
        log_info "✓ Helm lint passed"
        echo ""
        return 0
    else
        log_error "Helm lint failed. Check output above."
        return 1
    fi
}

render_helm_template() {
    local env=$1
    local namespace=$2
    local release=$3

    log_step "Rendering Helm template for environment: ${env}"

    # Build values file arguments
    local values_args="-f ${CHART_DIR}/base-config.yaml.gotmpl"

    # Check for environment-specific values file
    local env_values_file
    if [ -n "${VALUES_FILE_PATH}" ]; then
        env_values_file="${VALUES_FILE_PATH}"
    elif [ -f "${CHART_DIR}/${env}/values.yaml" ]; then
        env_values_file="${CHART_DIR}/${env}/values.yaml"
    else
        log_warn "No environment-specific values file found for '${env}'"
    fi

    if [ -n "${env_values_file}" ] && [ -f "${env_values_file}" ]; then
        values_args="${values_args} -f ${env_values_file}"
        log_info "Using values files:"
        log_info "  - ${CHART_DIR}/base-config.yaml.gotmpl"
        log_info "  - ${env_values_file}"
    else
        log_info "Using values file:"
        log_info "  - ${CHART_DIR}/base-config.yaml.gotmpl"
    fi

    # Export environment variables for gotmpl rendering
    export FORM_RECOGNIZER_KEY
    export FORM_RECOGNIZER_ENDPOINT_URI

    # Create output directory
    local output_dir="${SCRIPT_DIR}/rendered-manifests/${env}"
    mkdir -p "${output_dir}"

    # Render template
    log_info "Rendering template..."

    if helm template "${release}" "${CHART_DIR}" ${values_args} \
        --namespace "${namespace}" \
        --debug 2>&1 | tee "${output_dir}/debug.log" > "${output_dir}/all.yaml"; then

        log_info "✓ Template rendered successfully"
        log_info "Output saved to: ${output_dir}/all.yaml"

        # Show summary
        local resource_count
        resource_count=$(grep -c "^kind:" "${output_dir}/all.yaml" 2>/dev/null || echo "0")
        log_info "Total Kubernetes resources: ${resource_count}"

        # List resource types
        if [ "${resource_count}" -gt 0 ]; then
            log_info "Resource breakdown:"
            grep "^kind:" "${output_dir}/all.yaml" | sort | uniq -c | while read -r line; do
                echo "    ${line}"
            done
        fi

        echo ""
        return 0
    else
        log_error "Failed to render Helm template"
        log_error "Check debug output at: ${output_dir}/debug.log"
        return 1
    fi
}

validate_manifests() {
    local env=$1
    local output_dir="${SCRIPT_DIR}/rendered-manifests/${env}"

    log_step "Validating rendered manifests..."

    # Check if file exists and is not empty
    if [ ! -s "${output_dir}/all.yaml" ]; then
        log_error "Rendered manifest file is empty or does not exist"
        return 1
    fi

    # Dry-run validation with kubectl
    log_info "Running kubectl dry-run validation..."
    if kubectl apply --dry-run=client -f "${output_dir}/all.yaml" 2>&1 | tee "${output_dir}/validation.log"; then
        log_info "✓ Manifest validation passed"
        echo ""
        return 0
    else
        log_error "Manifest validation failed"
        log_error "Check validation output at: ${output_dir}/validation.log"
        return 1
    fi
}

helm_diff_check() {
    local env=$1
    local namespace=$2
    local release=$3

    log_step "Checking for differences with deployed release..."

    # Check if release exists
    if ! helm list -n "${namespace}" 2>/dev/null | grep -q "^${release}"; then
        log_info "Release '${release}' not found in namespace '${namespace}'"
        log_info "This will be a fresh installation"
        echo ""
        return 0
    fi

    log_info "Existing release found. Checking differences..."

    # Get current values
    helm get values "${release}" -n "${namespace}" > "/tmp/${release}-current-values.yaml" 2>/dev/null || true

    # Show current release info
    log_info "Current release info:"
    helm list -n "${namespace}" | grep "^${release}" || true

    echo ""
    log_warn "Note: Install 'helm diff' plugin for detailed comparison:"
    log_warn "  helm plugin install https://github.com/databus23/helm-diff"

    # Try to use helm diff if available
    if helm plugin list 2>/dev/null | grep -q "diff"; then
        log_info "Running helm diff..."

        local values_args="-f ${CHART_DIR}/base-config.yaml.gotmpl"
        local env_values_file
        if [ -n "${VALUES_FILE_PATH}" ]; then
            env_values_file="${VALUES_FILE_PATH}"
        elif [ -f "${CHART_DIR}/${env}/${env}-values.yaml" ]; then
            env_values_file="${CHART_DIR}/${env}/${env}-values.yaml"
        fi

        if [ -n "${env_values_file}" ] && [ -f "${env_values_file}" ]; then
            values_args="${values_args} -f ${env_values_file}"
        fi

        helm diff upgrade "${release}" "${CHART_DIR}" ${values_args} \
            --namespace "${namespace}" \
            --allow-unreleased || true
    fi

    echo ""
}

deploy_helm_chart() {
    local env=$1
    local namespace=$2
    local release=$3

    log_step "Deploying Helm chart..."

    # Build values file arguments
    local values_args="-f ${CHART_DIR}/base-config.yaml.gotmpl"

    # Check for environment-specific values file
    local env_values_file
    if [ -n "${VALUES_FILE_PATH}" ]; then
        env_values_file="${VALUES_FILE_PATH}"
    elif [ -f "${CHART_DIR}/${env}/${env}-values.yaml" ]; then
        env_values_file="${CHART_DIR}/${env}/${env}-values.yaml"
    fi

    if [ -n "${env_values_file}" ] && [ -f "${env_values_file}" ]; then
        values_args="${values_args} -f ${env_values_file}"
    fi

    # Check if namespace exists, create if not
    if ! kubectl get namespace "${namespace}" &> /dev/null; then
        log_info "Creating namespace: ${namespace}"
        kubectl create namespace "${namespace}"
    else
        log_info "Namespace '${namespace}' already exists"
    fi

    # Deploy with helm upgrade --install
    log_info "Executing: helm upgrade --install ${release} ${CHART_DIR}"
    log_info "  Namespace: ${namespace}"
    log_info "  Wait: enabled"
    log_info "  Timeout: 5m"

    echo ""

    if helm upgrade --install "${release}" "${CHART_DIR}" ${values_args} \
        --namespace "${namespace}" \
        --create-namespace \
        --wait \
        --timeout 5m \
        --atomic \
        --cleanup-on-fail 2>&1 | tee /tmp/helm-deploy.log; then

        log_info "✓ Deployment successful!"
        echo ""
        return 0
    else
        log_error "Deployment failed"
        log_error "Check logs at: /tmp/helm-deploy.log"
        echo ""
        log_info "To rollback, run:"
        log_info "  helm rollback ${release} -n ${namespace}"
        return 1
    fi
}

show_deployment_status() {
    local namespace=$1
    local release=$2

    log_step "Deployment Status"
    echo ""

    # Helm release status
    log_info "Helm Release:"
    helm list -n "${namespace}" | head -1
    helm list -n "${namespace}" | grep "${release}" || log_warn "Release not found"
    echo ""

    # Get release details
    log_info "Release History:"
    helm history "${release}" -n "${namespace}" --max 5 2>/dev/null || log_warn "No history available"
    echo ""

    # Pods
    log_info "Pods:"
    kubectl get pods -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o wide 2>/dev/null || log_warn "No pods found"
    echo ""

    # Services
    log_info "Services:"
    kubectl get svc -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o wide 2>/dev/null || log_warn "No services found"
    echo ""

    # PVCs
    log_info "PersistentVolumeClaims:"
    kubectl get pvc -n "${namespace}" -l "app.kubernetes.io/instance=${release}" 2>/dev/null || log_warn "No PVCs found"
    echo ""

    # Secrets
    log_info "Secrets:"
    kubectl get secrets -n "${namespace}" -l "app.kubernetes.io/instance=${release}" 2>/dev/null || log_warn "No secrets found"
    echo ""

    # Check pod status
    local pod_name
    pod_name=$(kubectl get pods -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "${pod_name}" ]; then
        log_info "Pod Events (last 10):"
        kubectl get events -n "${namespace}" --field-selector involvedObject.name="${pod_name}" --sort-by='.lastTimestamp' | tail -10 || true
        echo ""

        log_info "To view logs, run:"
        log_info "  kubectl logs -n ${namespace} ${pod_name} -f"
        echo ""

        log_info "To access the service, run:"
        log_info "  kubectl -n ${namespace} port-forward svc/${release}-azure-docintel-layout 5000:5000"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    # Parse arguments
    if [ $# -lt 2 ]; then
        usage
    fi

    local environment=$1
    local namespace=$2

    echo ""
    log_info "==================================================================="
    log_info "  Azure Form Recognizer Layout - Helm Deployment"
    log_info "==================================================================="
    log_info "Environment:     ${environment}"
    log_info "Namespace:       ${namespace}"
    log_info "Release:         ${RELEASE_NAME}"
    log_info "Chart Directory: ${CHART_DIR}"
    log_info "Dry Run:         ${DRY_RUN}"
    log_info "==================================================================="
    echo ""

    # Step 1: Prerequisites
    check_prerequisites

    # Step 2: Kubernetes context
    check_kubernetes_context

    # Step 3: Helm lint
    if ! helm_lint_chart; then
        log_error "Helm lint failed. Fix chart issues before deploying."
        exit 1
    fi

    # Step 4: Render template
    if ! render_helm_template "${environment}" "${namespace}" "${RELEASE_NAME}"; then
        log_error "Template rendering failed. Aborting deployment."
        exit 1
    fi

    # Step 5: Validate manifests
    if ! validate_manifests "${environment}"; then
        log_error "Manifest validation failed. Aborting deployment."
        exit 1
    fi

    # Step 6: Check differences
    helm_diff_check "${environment}" "${namespace}" "${RELEASE_NAME}"

    # Step 7: Deploy or skip based on DRY_RUN
    if [ "${DRY_RUN}" = "true" ]; then
        log_warn "DRY_RUN mode enabled. Skipping actual deployment."
        log_info "Rendered manifests are available at:"
        log_info "  ${SCRIPT_DIR}/rendered-manifests/${environment}/all.yaml"
        echo ""
        log_info "To deploy, run without DRY_RUN:"
        log_info "  $0 ${environment} ${namespace} ${RELEASE_NAME}"
        exit 0
    fi

    # Confirm deployment
    if [ "${SKIP_CONFIRM}" != "true" ]; then
        echo ""
        log_warn "Ready to deploy to:"
        log_warn "  Namespace: ${namespace}"
        log_warn "  Release:   ${RELEASE_NAME}"
        log_warn "  Context:   $(kubectl config current-context)"
        echo ""
        read -p "Proceed with deployment? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy](es)?$ ]]; then
            log_error "Deployment cancelled by user"
            exit 1
        fi
    fi

    echo ""

    # Step 8: Deploy
    if deploy_helm_chart "${environment}" "${namespace}" "${RELEASE_NAME}"; then
        echo ""
        show_deployment_status "${namespace}" "${RELEASE_NAME}"
        echo ""
        log_info "==================================================================="
        log_info "  ✓ Deployment completed successfully!"
        log_info "==================================================================="
        exit 0
    else
        log_error "==================================================================="
        log_error "  ✗ Deployment failed"
        log_error "==================================================================="
        exit 1
    fi
}

# Run main
main "$@"

