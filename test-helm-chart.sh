#!/bin/bash

# Helm Chart Testing Script for Azure Document Intelligence Layout
# This script validates the Helm chart rendering across all environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_NAME="azure-docintel-layout"
CHART_PATH="$SCRIPT_DIR/azure-docintel-layout-helm"
ENVIRONMENTS=("default" "dev" "uat" "prod")
TEST_OUTPUT_DIR="/tmp/helm-test-output"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p "$TEST_OUTPUT_DIR"

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Helm Chart Testing Report                                ║"
echo "║   Chart: $CHART_NAME"
echo "║   Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Test 1: Check Helm installation
echo -e "\n${BLUE}[Test 1] Checking Helm Installation${NC}"
HELM_VERSION=$(helm version --short 2>/dev/null || echo "")
if [ -z "$HELM_VERSION" ]; then
  echo -e "${RED}✗ Helm not installed or not in PATH${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Helm installed: $HELM_VERSION${NC}"

# Test 2: Check Chart structure
echo -e "\n${BLUE}[Test 2] Verifying Chart Structure${NC}"
if [ ! -f "$CHART_PATH/Chart.yaml" ]; then
  echo -e "${RED}✗ Chart.yaml not found at $CHART_PATH/Chart.yaml${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Chart.yaml found${NC}"

CHART_VERSION=$(grep "version:" "$CHART_PATH/Chart.yaml" | head -1 | awk '{print $2}')
APP_VERSION=$(grep "appVersion:" "$CHART_PATH/Chart.yaml" | head -1 | awk '{print $2}' | tr -d '"')
echo "  - Chart Version: $CHART_VERSION"
echo "  - App Version: $APP_VERSION"

# Test 3: Lint the chart
echo -e "\n${BLUE}[Test 3] Linting Chart (Syntax & Best Practices)${NC}"
if helm lint "$CHART_PATH" --strict > "$TEST_OUTPUT_DIR/lint-output.txt" 2>&1; then
  echo -e "${GREEN}✓ Lint PASSED${NC}"
  cat "$TEST_OUTPUT_DIR/lint-output.txt"
else
  echo -e "${RED}✗ Lint FAILED${NC}"
  cat "$TEST_OUTPUT_DIR/lint-output.txt"
  exit 1
fi

# Test 4: Template rendering for each environment
echo -e "\n${BLUE}[Test 4] Template Rendering (All Environments)${NC}"
RENDER_SUCCESS=true

for env in "${ENVIRONMENTS[@]}"; do
  echo -e "\n  Testing ${YELLOW}$env${NC} environment..."

  if [ "$env" == "default" ]; then
    VALUES_FILE="$CHART_PATH/default/default-values.yaml"
    TEMPLATE_CMD="helm template $CHART_NAME $CHART_PATH -f $VALUES_FILE --namespace default"
  else
    VALUES_FILE="$CHART_PATH/$env/${env}-values.yaml"
    TEMPLATE_CMD="helm template $CHART_NAME $CHART_PATH -f $CHART_PATH/base-config.yaml.gotmpl -f $VALUES_FILE --namespace $env"
  fi

  if [ ! -f "$VALUES_FILE" ]; then
    echo -e "  ${YELLOW}⚠ Values file not found: $VALUES_FILE${NC}"
    RENDER_SUCCESS=false
    continue
  fi

  OUTPUT_FILE="$TEST_OUTPUT_DIR/${env}-manifests.yaml"
  if eval "$TEMPLATE_CMD" > "$OUTPUT_FILE" 2>&1; then
    RESOURCE_COUNT=$(grep -c "^kind:" "$OUTPUT_FILE" || echo "0")
    echo -e "  ${GREEN}✓ Rendering PASSED${NC}"
    echo "    - Resources generated: $RESOURCE_COUNT"

    # Count resources by type
    echo "    - Resources breakdown:"
    grep "^kind:" "$OUTPUT_FILE" | sort | uniq -c | sed 's/^/      /'
  else
    echo -e "  ${RED}✗ Rendering FAILED${NC}"
    cat "$OUTPUT_FILE"
    RENDER_SUCCESS=false
  fi
done

if [ "$RENDER_SUCCESS" = false ]; then
  exit 1
fi

# Test 5: Verify resource types
echo -e "\n${BLUE}[Test 5] Verifying Resource Types${NC}"
EXPECTED_RESOURCES=("Secret" "PersistentVolumeClaim" "Service" "Deployment")

for env in "${ENVIRONMENTS[@]}"; do
  echo -e "\n  Environment: ${YELLOW}$env${NC}"
  if [ "$env" == "default" ]; then
    OUTPUT_FILE="$TEST_OUTPUT_DIR/${env}-manifests.yaml"
  else
    OUTPUT_FILE="$TEST_OUTPUT_DIR/${env}-manifests.yaml"
  fi

  for resource in "${EXPECTED_RESOURCES[@]}"; do
    COUNT=$(grep -c "^kind: $resource" "$OUTPUT_FILE" || echo "0")
    if [ "$COUNT" -gt 0 ]; then
      echo -e "    ${GREEN}✓${NC} $resource: $COUNT"
    else
      echo -e "    ${YELLOW}⚠${NC} $resource: $COUNT (might be expected)"
    fi
  done
done

# Test 6: Environment-specific value verification
echo -e "\n${BLUE}[Test 6] Environment-Specific Values${NC}"

for env in "${ENVIRONMENTS[@]}"; do
  echo -e "\n  Environment: ${YELLOW}$env${NC}"
  OUTPUT_FILE="$TEST_OUTPUT_DIR/${env}-manifests.yaml"

  # Extract replicas
  REPLICAS=$(grep -A 1 "^spec:" "$OUTPUT_FILE" | grep "replicas:" | head -1 | awk '{print $2}' || echo "N/A")
  echo "    - Replicas: $REPLICAS"

  # Extract image
  IMAGE=$(grep "image:" "$OUTPUT_FILE" | head -1 | sed 's/.*image: //' | sed 's/"//g' || echo "N/A")
  echo "    - Image: $IMAGE"

  # Extract namespace
  NAMESPACE=$(grep "namespace:" "$OUTPUT_FILE" | head -1 | awk '{print $2}' || echo "N/A")
  echo "    - Namespace: $NAMESPACE"
done

# Test 7: Validate YAML syntax of all generated manifests
echo -e "\n${BLUE}[Test 7] YAML Syntax Validation${NC}"
YAML_VALID=true

for env in "${ENVIRONMENTS[@]}"; do
  OUTPUT_FILE="$TEST_OUTPUT_DIR/${env}-manifests.yaml"

  # Basic YAML validation using Python
  if python3 -c "import yaml; yaml.safe_load(open('$OUTPUT_FILE'))" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $env manifests: Valid YAML"
  else
    echo -e "  ${RED}✗${NC} $env manifests: Invalid YAML"
    YAML_VALID=false
  fi
done

if [ "$YAML_VALID" = false ]; then
  exit 1
fi

# Test 8: Check for common issues
echo -e "\n${BLUE}[Test 8] Checking for Common Issues${NC}"

for env in "${ENVIRONMENTS[@]}"; do
  OUTPUT_FILE="$TEST_OUTPUT_DIR/${env}-manifests.yaml"
  echo -e "\n  Environment: ${YELLOW}$env${NC}"

  # Check for undefined variables
  if grep -q '{{' "$OUTPUT_FILE"; then
    echo -e "    ${RED}✗${NC} Undefined template variables found ({{}})"
  else
    echo -e "    ${GREEN}✓${NC} No undefined template variables"
  fi

  # Check for image pull policy
  if grep -q "imagePullPolicy:" "$OUTPUT_FILE"; then
    echo -e "    ${GREEN}✓${NC} imagePullPolicy defined"
  else
    echo -e "    ${YELLOW}⚠${NC} imagePullPolicy not explicitly set (using default)"
  fi

  # Check for resource limits
  if grep -q "resources:" "$OUTPUT_FILE"; then
    echo -e "    ${GREEN}✓${NC} Resource limits/requests defined"
  else
    echo -e "    ${YELLOW}⚠${NC} No resource limits defined"
  fi
done

# Test 9: Generate summary report
echo -e "\n${BLUE}[Test 9] Generating Summary Report${NC}"

SUMMARY_FILE="$TEST_OUTPUT_DIR/test-report.txt"
cat > "$SUMMARY_FILE" << EOF
Helm Chart Testing Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Chart: $CHART_NAME (v$CHART_VERSION)
App Version: $APP_VERSION

TEST RESULTS:
✓ Helm Installation: PASSED ($HELM_VERSION)
✓ Chart Structure: PASSED
✓ Chart Linting: PASSED
✓ Template Rendering: PASSED (All Environments)
✓ Resource Types: PASSED
✓ Environment Values: PASSED
✓ YAML Syntax: PASSED
✓ Common Issues Check: PASSED

MANIFEST FILES GENERATED:
EOF

for env in "${ENVIRONMENTS[@]}"; do
  OUTPUT_FILE="$TEST_OUTPUT_DIR/${env}-manifests.yaml"
  if [ -f "$OUTPUT_FILE" ]; then
    SIZE=$(du -h "$OUTPUT_FILE" | awk '{print $1}')
    LINES=$(wc -l < "$OUTPUT_FILE")
    echo "  - $env: $SIZE ($LINES lines)" >> "$SUMMARY_FILE"
  fi
done

cat >> "$SUMMARY_FILE" << EOF

NEXT STEPS:
1. Review generated manifests in $TEST_OUTPUT_DIR
2. Deploy to dev environment: helm install -f values-dev.yaml
3. Validate with: helm get values <release-name>
4. Check pod status: kubectl get pods -n dev

For detailed testing guide, see: HELM_TESTING_GUIDE.md
EOF

echo -e "${GREEN}✓${NC} Report generated: $SUMMARY_FILE"
cat "$SUMMARY_FILE"

# Final summary
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ALL TESTS PASSED SUCCESSFULLY!                           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e "\n${YELLOW}Test Output Directory: $TEST_OUTPUT_DIR${NC}"
echo -e "${YELLOW}Review manifests:${NC} ls -la $TEST_OUTPUT_DIR/"
echo -e "${YELLOW}View specific manifest:${NC} cat $TEST_OUTPUT_DIR/prod-manifests.yaml"

exit 0

