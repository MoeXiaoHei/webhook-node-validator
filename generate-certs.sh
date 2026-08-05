#!/bin/bash
# 生成 Webhook 所需的 TLS 证书

set -e

NAMESPACE="my-namespace"
SERVICE_NAME="webhook-service"
CERT_DIR="./certs"

mkdir -p ${CERT_DIR}
cd ${CERT_DIR}

# 生成 CA 私钥和证书
openssl genrsa -out ca.key 2048
openssl req -new -x509 -days 365 -key ca.key -out ca.crt -subj "/CN=webhook-ca"

# 生成 Webhook 服务私钥和证书签名请求
openssl genrsa -out webhook.key 2048
openssl req -new -key webhook.key -out webhook.csr -subj "/CN=${SERVICE_NAME}.${NAMESPACE}.svc"

# 使用 CA 签署证书
cat > webhook.conf <<EOF
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${SERVICE_NAME}
DNS.2 = ${SERVICE_NAME}.${NAMESPACE}
DNS.3 = ${SERVICE_NAME}.${NAMESPACE}.svc
DNS.4 = ${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local
EOF

openssl x509 -req -days 365 -in webhook.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out webhook.crt -extensions v3_req -extfile webhook.conf

echo "✅ Certificates generated successfully!"
echo "CA Certificate: $(cat ca.crt | base64 | tr -d '\n')"
