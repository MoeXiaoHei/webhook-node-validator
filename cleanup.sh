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
NC='\033[0m'

print_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }

echo -e "${BOLD}${YELLOW}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║           🧹  Webhook Node Validator Cleanup                ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. 删除 ValidatingWebhookConfiguration
print_header "📋 Deleting ValidatingWebhookConfiguration"
kubectl delete validatingwebhookconfiguration node-validation-webhook --ignore-not-found=true 2>/dev/null && print_success "ValidatingWebhookConfiguration deleted" || print_info "Not found, skipping"

# 2. 删除 Webhook Service
print_header "🌐 Deleting Webhook Service"
kubectl delete service webhook-service -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "Service deleted" || print_info "Not found, skipping"

# 3. 删除 Webhook Deployment
print_header "🚀 Deleting Webhook Deployment"
kubectl delete deployment node-validation-webhook -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "Deployment deleted" || print_info "Not found, skipping"

# 4. 删除 TLS Secret
print_header "🔑 Deleting TLS Secrets"
kubectl delete secret webhook-tls -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "webhook-tls deleted" || print_info "Not found, skipping"
kubectl delete secret webhook-ca -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "webhook-ca deleted" || print_info "Not found, skipping"

# 5. 删除 ConfigMap
print_header "📝 Deleting ConfigMap"
kubectl delete configmap webhook-code -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "ConfigMap deleted" || print_info "Not found, skipping"

# 6. 删除 RBAC
print_header "🛡️  Deleting RBAC"
kubectl delete clusterrolebinding node-reader-binding --ignore-not-found=true 2>/dev/null && print_success "node-reader-binding deleted" || print_info "Not found, skipping"
kubectl delete clusterrolebinding webhook-validator-binding --ignore-not-found=true 2>/dev/null && print_success "webhook-validator-binding deleted" || print_info "Not found, skipping"
kubectl delete clusterrole node-reader --ignore-not-found=true 2>/dev/null && print_success "node-reader deleted" || print_info "Not found, skipping"
kubectl delete clusterrole webhook-validator --ignore-not-found=true 2>/dev/null && print_success "webhook-validator deleted" || print_info "Not found, skipping"
kubectl delete rolebinding pod-full-control-binding -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "pod-full-control-binding deleted" || print_info "Not found, skipping"
kubectl delete role pod-full-control -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "pod-full-control deleted" || print_info "Not found, skipping"

# 7. 删除 ServiceAccount
print_header "🔐 Deleting ServiceAccounts"
kubectl delete serviceaccount multi-node-operator-sa -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "multi-node-operator-sa deleted" || print_info "Not found, skipping"
kubectl delete serviceaccount webhook-sa -n my-namespace --ignore-not-found=true 2>/dev/null && print_success "webhook-sa deleted" || print_info "Not found, skipping"

# 8. 移除命名空间标签
print_header "🏷️  Removing Namespace Label"
kubectl label namespace my-namespace webhook-enabled- 2>/dev/null && print_success "Label removed" || print_info "Label not found, skipping"

# 9. 删除 MutatingWebhookConfiguration
print_header "📋 Deleting MutatingWebhookConfiguration"
kubectl delete mutatingwebhookconfiguration node-selector-webhook --ignore-not-found=true 2>/dev/null && print_success "MutatingWebhookConfiguration deleted" || print_info "Not found, skipping"

# 10. 删除节点标签
print_header "🏷️  Removing Node Labels"
ALLOWED_NODES="hadoop02 example.com227 kg-lab-83-91"
for node in $ALLOWED_NODES; do
    kubectl label node "$node" allowed-node- 2>/dev/null && print_success "Label removed from $node" || print_info "Label not found on $node"
done

# 11. 询问是否删除命名空间（修复版）
print_header "🗑️  Namespace Cleanup"
echo -e -n "${YELLOW}❓ Do you want to delete the entire namespace 'my-namespace'? (y/N): ${NC}"
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete namespace my-namespace --ignore-not-found=true 2>/dev/null && print_success "Namespace 'my-namespace' deleted" || print_error "Failed to delete namespace"
else
    print_info "Namespace preserved. You can delete it later with: ${WHITE}kubectl delete namespace my-namespace${NC}"
fi

# 12. 删除证书文件（修复版）
print_header "📜 Certificate Files Cleanup"
echo -e -n "${YELLOW}❓ Do you want to delete the 'certs' directory? (y/N): ${NC}"
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf certs/ && print_success "Certificates deleted!" || print_warning "Failed to delete certs/"
else
    print_info "Certificates preserved at ${WHITE}./certs/${NC}"
fi

echo -e "\n${BOLD}${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ✅  Cleanup complete!${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
