#!/bin/bash
set -e

# ==================== 颜色定义 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ==================== 函数定义 ====================
print_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_step() {
    echo -e "\n${BOLD}${MAGENTA}▶${NC} ${BOLD}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_token() {
    echo -e "${BOLD}${WHITE}🔑 ServiceAccount Token:${NC}"
    echo -e "${GREEN}$1${NC}"
}

print_test_cmd() {
    echo -e "${WHITE}  $1${NC}"
    echo -e "${YELLOW}  $2${NC}"
}

# ==================== 主流程 ====================
echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║           🚀  Webhook Node Validator Deployer               ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. 生成证书
print_header "📜 Step 1: Generating TLS Certificates"
if [ -f "./generate-certs.sh" ]; then
    ./generate-certs.sh
    print_success "Certificates generated successfully!"
else
    print_error "generate-certs.sh not found!"
    exit 1
fi

# 2. 创建命名空间
print_header "📁 Step 2: Creating Namespace"
kubectl create namespace my-namespace --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
print_success "Namespace 'my-namespace' created/exists"

# 3. 创建 ServiceAccount
print_header "🔐 Step 3: Creating ServiceAccounts"
if kubectl apply -f 1-serviceaccount.yaml > /dev/null 2>&1; then
    print_success "ServiceAccounts created successfully"
else
    print_error "Failed to create ServiceAccounts"
    exit 1
fi

# 4. 创建 RBAC
print_header "🛡️  Step 4: Creating RBAC"
if kubectl apply -f 2-rbac.yaml > /dev/null 2>&1; then
    print_success "RBAC created successfully"
else
    print_error "Failed to create RBAC"
    exit 1
fi

# 5. 创建 ConfigMap
print_header "📝 Step 5: Creating Webhook Code ConfigMap"
if kubectl apply -f 3-webhook-code-configmap.yaml > /dev/null 2>&1; then
    print_success "ConfigMap created successfully"
else
    print_error "Failed to create ConfigMap"
    exit 1
fi

# 6. 创建 TLS Secret
print_header "🔑 Step 6: Creating TLS Secret"
if kubectl create secret tls webhook-tls \
    --cert=certs/webhook.crt \
    --key=certs/webhook.key \
    --namespace my-namespace \
    --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1; then
    print_success "TLS Secret created successfully"
else
    print_error "Failed to create TLS Secret"
    exit 1
fi

# 7. 创建 Deployment
print_header "🚀 Step 7: Deploying Webhook Service"
if kubectl apply -f 5-webhook-deployment.yaml > /dev/null 2>&1; then
    print_success "Deployment created successfully"
else
    print_error "Failed to create Deployment"
    exit 1
fi

# 8. 创建 Service
print_header "🌐 Step 8: Creating Webhook Service"
if kubectl apply -f 6-webhook-service.yaml > /dev/null 2>&1; then
    print_success "Service created successfully"
else
    print_error "Failed to create Service"
    exit 1
fi

# 9. 等待 Deployment 就绪
print_header "⏳ Step 9: Waiting for Deployment to be Ready"
print_info "Waiting for pods to be ready (timeout: 180s)..."
if kubectl wait --for=condition=ready pod -l app=node-validation-webhook -n my-namespace --timeout=180s > /dev/null 2>&1; then
    print_success "All pods are ready!"
else
    print_warning "Pods not ready within timeout, checking status..."
    kubectl get pods -n my-namespace -l app=node-validation-webhook
fi

# 10. 创建 ValidatingWebhookConfiguration
print_header "📋 Step 10: Creating ValidatingWebhookConfiguration"
CA_BUNDLE=$(cat certs/ca.crt | base64 | tr -d '\n')
if cat 7-validating-webhook.yaml | sed "s/<BASE64_ENCODED_CA_CERT>/${CA_BUNDLE}/g" | kubectl apply -f - > /dev/null 2>&1; then
    print_success "ValidatingWebhookConfiguration created successfully"
else
    print_error "Failed to create ValidatingWebhookConfiguration"
    exit 1
fi

# 11. 创建 MutatingWebhookConfiguration
print_header "📋 Step 11: Creating MutatingWebhookConfiguration"
if [ -f "9-mutating-webhook.yaml" ]; then
    if cat 9-mutating-webhook.yaml | sed "s/<BASE64_ENCODED_CA_CERT>/${CA_BUNDLE}/g" | kubectl apply -f - > /dev/null 2>&1; then
        print_success "MutatingWebhookConfiguration created successfully"
    else
        print_warning "Failed to create MutatingWebhookConfiguration"
    fi
else
    print_warning "9-mutating-webhook.yaml not found, skipping..."
fi

# 12. 给命名空间打标签
print_header "🏷️  Step 12: Labeling Namespace"
if kubectl label namespace my-namespace webhook-enabled=true --overwrite > /dev/null 2>&1; then
    print_success "Namespace labeled successfully"
else
    print_warning "Failed to label namespace"
fi

# 13. 给白名单节点打标签
print_header "🏷️  Step 13: Labeling Allowed Nodes"
ALLOWED_NODES=$(kubectl get deployment node-validation-webhook -n my-namespace -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ALLOWED_NODES")].value}' 2>/dev/null || echo "hadoop02,example.com227,kg-lab-83-91")
IFS=',' read -ra NODE_ARRAY <<< "$ALLOWED_NODES"
for node in "${NODE_ARRAY[@]}"; do
    node=$(echo "$node" | xargs)  # trim whitespace
    if kubectl label node "$node" allowed-node=true --overwrite 2>/dev/null; then
        print_success "Node '$node' labeled"
    else
        print_warning "Node '$node' not found or cannot be labeled"
    fi
done

# 14. 获取 Token
print_header "🎫 Step 14: Getting ServiceAccount Token"
SA_SECRET=$(kubectl get serviceaccount multi-node-operator-sa -n my-namespace -o jsonpath='{.secrets[0].name}' 2>/dev/null)
if [ -n "$SA_SECRET" ]; then
    TOKEN=$(kubectl get secret ${SA_SECRET} -n my-namespace -o jsonpath='{.data.token}' | base64 -d)
    print_success "Token retrieved successfully"
else
    print_warning "ServiceAccount token not found, creating..."
    # 创建 token secret (Kubernetes 1.24+ 需要手动创建)
    cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: multi-node-operator-sa-token
  namespace: my-namespace
  annotations:
    kubernetes.io/service-account.name: multi-node-operator-sa
type: kubernetes.io/service-account-token
EOF
    sleep 3
    SA_SECRET=$(kubectl get serviceaccount multi-node-operator-sa -n my-namespace -o jsonpath='{.secrets[0].name}')
    TOKEN=$(kubectl get secret ${SA_SECRET} -n my-namespace -o jsonpath='{.data.token}' | base64 -d)
    print_success "Token created and retrieved"
fi

# ==================== 输出结果 ====================
clear
echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║              ✅  DEPLOYMENT COMPLETE!                       ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_token "${TOKEN}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "\n${BOLD}${WHITE}📝 Test Commands:${NC}"
echo ""
print_test_cmd "# 1️⃣  不指定 nodeName，自动调度到白名单节点"
echo -e "${GREEN}kubectl run test-pod --image=nginx --restart=Never -n my-namespace --token=${TOKEN}${NC}"

echo ""
print_test_cmd "# 2️⃣  指定 nodeName（必须在白名单中）"
echo -e "${GREEN}kubectl run test-pod-2 --image=nginx --restart=Never -n my-namespace --overrides='{\"spec\":{\"nodeName\":\"node-01\"}}' --token=${TOKEN}${NC}"

echo ""
print_test_cmd "# 3️⃣  指定非白名单节点（会被拒绝）"
echo -e "${GREEN}kubectl run test-pod-3 --image=nginx --restart=Never -n my-namespace --overrides='{\"spec\":{\"nodeName\":\"node-02\"}}' --token=${TOKEN}${NC}"

echo ""
print_test_cmd "# 4️⃣  查看 Pod 调度到哪个节点"
echo -e "${GREEN}kubectl get pods -n my-namespace -o wide${NC}"

echo ""
print_test_cmd "# 5️⃣  清理测试 Pod"
echo -e "${GREEN}kubectl delete pod test-pod test-pod-2 test-pod-3 -n my-namespace --ignore-not-found=true${NC}"

echo -e "\n${BOLD}${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  🎉  All done! Happy kubernetes!${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
