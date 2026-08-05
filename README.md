# Webhook Node Validator

一个 Kubernetes Validating + Mutating Admission Webhook，用于限制 Pod 只能调度到指定的节点。

## ✨ 功能特性

- ✅ **节点白名单**：只允许 Pod 调度到指定的节点
- ✅ **自动注入 NodeSelector**：无需手动指定节点，自动调度到白名单节点
- ✅ **灵活的 Pod 创建方式**：支持指定节点或不指定节点
- ✅ **命名空间级别控制**：通过 `namespaceSelector` 精确控制 Webhook 生效范围
- ✅ **RBAC 权限控制**：通过 ServiceAccount + RBAC 精细化控制权限
- ✅ **生产级部署**：支持多副本、滚动更新、健康检查
- ✅ **彩色输出**：部署和清理脚本带颜色区分，易于阅读

---

## 📋 目录结构

```
webhook-node-validator/
├── 1-serviceaccount.yaml # ServiceAccount 定义
├── 2-rbac.yaml # RBAC 权限定义
├── 3-webhook-code-configmap.yaml # Webhook Python 代码
├── 5-webhook-deployment.yaml # Webhook Deployment
├── 6-webhook-service.yaml # Webhook Service
├── 7-validating-webhook.yaml # ValidatingWebhookConfiguration
├── 9-mutating-webhook.yaml # MutatingWebhookConfiguration
├── deploy.sh # 一键部署脚本（带颜色）
├── cleanup.sh # 一键清理脚本（带颜色）
├── generate-certs.sh # 证书生成脚本
├── Dockerfile # 自定义镜像构建文件
└── README.md # 本文件
```

## 🚀 快速开始

### 前置条件

- Kubernetes 集群（版本 v1.19+）
- `kubectl` 已配置
- OpenSSL（用于生成证书）

### 1. 下载文件

将本目录所有文件下载到本地。

### 2. 修改配置

#### 修改允许的节点列表

编辑 `5-webhook-deployment.yaml`，修改 `ALLOWED_NODES` 环境变量：

```yaml
env:
- name: ALLOWED_NODES
  value: "node-01,node-02"  # 改为你的白名单节点
```



#### 修改命名空间（可选）

默认使用 `my-namespace`，如需修改，在所有 YAML 文件中替换 `my-namespace` 为你的命名空间。

### 3. 一键部署

bash

```
# 给脚本添加执行权限
chmod +x deploy.sh cleanup.sh generate-certs.sh

# 执行部署
./deploy.sh
```



部署完成后会输出：

- ServiceAccount Token（用于后续 API 调用）
- 测试命令示例

------

## 🔧 工作原理

### 架构图

text

```
用户请求创建 Pod
        │
        ▼
┌───────────────────┐
│  认证 (Authn)      │  ← 检查 Token 是否有效
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  授权 (Authz)      │  ← RBAC 检查是否有 create pods 权限
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  MutatingWebhook  │  ← 自动注入 nodeSelector: {"allowed-node":"true"}
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ ValidatingWebhook │  ← 检查 nodeName 是否在白名单中
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  调度器 (Scheduler)│  ← 根据 nodeSelector 调度到白名单节点
└───────────────────┘
```



### 核心组件

| 组件                  | 作用                                          |
| :-------------------- | :-------------------------------------------- |
| **ServiceAccount**    | 为客户端提供身份认证 Token                    |
| **RBAC**              | 控制客户端对 Pod 的操作权限                   |
| **MutatingWebhook**   | 自动注入 `nodeSelector`，限制调度到白名单节点 |
| **ValidatingWebhook** | 校验 `nodeName` 是否在白名单中                |
| **NodeSelector**      | 通过节点标签 `allowed-node=true` 限制调度     |

------

## 📝 使用方法

### 获取 Token

部署完成后，Token 会显示在控制台输出中。如果忘记保存，可以重新获取：

bash

```
# 获取 ServiceAccount 对应的 Secret
SA_SECRET=$(kubectl get serviceaccount multi-node-operator-sa -n my-namespace -o jsonpath='{.secrets[0].name}')

# 获取 Token
TOKEN=$(kubectl get secret ${SA_SECRET} -n my-namespace -o jsonpath='{.data.token}' | base64 -d)

echo ${TOKEN}
```



### 创建 Pod（方式一：不指定节点）

自动调度到白名单节点：

bash

```
kubectl run my-pod \
  --image=nginx:latest \
  --restart=Never \
  -n my-namespace \
  --token=${TOKEN}
```



### 创建 Pod（方式二：指定节点）

必须指定白名单中的节点：

bash

```
kubectl run my-pod \
  --image=nginx:latest \
  --restart=Never \
  -n my-namespace \
  --overrides='{"spec":{"nodeName":"node-01"}}' \
  --token=${TOKEN}
```



### 创建 Pod（方式三：使用 Deployment）

bash

```
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-namespace
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: nginx
        image: nginx:latest
EOF
```



### 查看 Pod 调度结果

bash

```
kubectl get pods -n my-namespace -o wide
```



------

## 🎯 命名空间级别控制（namespaceSelector）

### 什么是 namespaceSelector？

`namespaceSelector` 是 Admission Webhook 的配置项，用于**控制 Webhook 在哪些命名空间生效**。

yaml

```
namespaceSelector:
  matchLabels:
    webhook-enabled: "true"  # 只有打了这个标签的命名空间才生效
```



### 为什么需要 namespaceSelector？

1. **灰度测试**：先在测试命名空间验证，确认无误再扩展到生产
2. **故障隔离**：如果 Webhook 有问题，可以快速移除标签回滚
3. **灵活控制**：可以为不同的命名空间启用或禁用 Webhook
4. **最小影响**：避免影响系统命名空间（如 kube-system）

### 配置方式

#### 方式一：只对特定命名空间生效（默认配置）

yaml

```
namespaceSelector:
  matchLabels:
    webhook-enabled: "true"
```



**启用命名空间：**

bash

```
kubectl label namespace my-namespace webhook-enabled=true
```



**禁用命名空间：**

bash

```
kubectl label namespace my-namespace webhook-enabled-
```



#### 方式二：对所有命名空间生效

yaml

```
# 删除 namespaceSelector 配置，或设置为空
namespaceSelector: {}
```



#### 方式三：排除特定命名空间

yaml

```
namespaceSelector:
  matchExpressions:
  - key: kubernetes.io/metadata.name
    operator: NotIn
    values: ["kube-system", "kube-public"]
```



### 查看当前配置

bash

```
# 查看 ValidatingWebhook 的 namespaceSelector
kubectl get validatingwebhookconfiguration node-validation-webhook -o yaml | grep -A 5 namespaceSelector

# 查看命名空间标签
kubectl get namespaces --show-labels
```



------

## 🧪 测试

### 测试 1：不指定节点（应该成功）

bash

```
kubectl run test-auto \
  --image=nginx:latest \
  --restart=Never \
  -n my-namespace \
  --token=${TOKEN}

kubectl get pod test-auto -n my-namespace -o wide
kubectl delete pod test-auto -n my-namespace
```



### 测试 2：指定白名单节点（应该成功）

bash

```
kubectl run test-allowed \
  --image=nginx:latest \
  --restart=Never \
  -n my-namespace \
  --overrides='{"spec":{"nodeName":"node-01"}}' \
  --token=${TOKEN}

kubectl get pod test-allowed -n my-namespace -o wide
kubectl delete pod test-allowed -n my-namespace
```



### 测试 3：指定非白名单节点（应该被拒绝）

bash

```
kubectl run test-denied \
  --image=nginx:latest \
  --restart=Never \
  -n my-namespace \
  --overrides='{"spec":{"nodeName":"node-03"}}' \
  --token=${TOKEN}

# 预期输出：
# Error from server: admission webhook "node-validation.my-namespace.svc" denied the request: Node 'node-03' is not allowed.
```



### 测试 4：无标签命名空间（Webhook 不生效）

bash

```
# 在 default 命名空间创建 Pod（如果没有 webhook-enabled=true 标签）
kubectl run test-default \
  --image=nginx:latest \
  --restart=Never \
  -n default \
  --token=${TOKEN}

kubectl delete pod test-default -n default
```



------

## 🔍 监控与调试

### 查看 Webhook 状态

bash

```
# 查看 Pod 状态
kubectl get pods -n my-namespace -l app=node-validation-webhook

# 查看日志
kubectl logs -f -n my-namespace -l app=node-validation-webhook

# 查看 Deployment 状态
kubectl get deployment node-validation-webhook -n my-namespace
```



### 查看 Webhook 配置

bash

```
# 查看 ValidatingWebhookConfiguration
kubectl get validatingwebhookconfiguration node-validation-webhook -o yaml

# 查看 MutatingWebhookConfiguration
kubectl get mutatingwebhookconfiguration node-selector-webhook -o yaml
```



### 常见问题排查

| 问题               | 可能原因                 | 解决方案                                                    |
| :----------------- | :----------------------- | :---------------------------------------------------------- |
| Pod 无法创建       | Webhook 拒绝             | 检查节点名是否在白名单中                                    |
| Webhook 不生效     | 命名空间没有标签         | `kubectl label namespace my-namespace webhook-enabled=true` |
| 所有命名空间都生效 | 删除了 namespaceSelector | 重新添加 namespaceSelector                                  |
| 证书错误           | 证书过期或不匹配         | 重新生成证书 `./generate-certs.sh`                          |
| Pod 一直 Pending   | 没有可用节点             | 检查节点是否有 `allowed-node=true` 标签                     |

------

## 🧹 清理

### 一键清理

bash

```
./cleanup.sh
```



### 手动清理

bash

```
# 删除 ValidatingWebhookConfiguration
kubectl delete validatingwebhookconfiguration node-validation-webhook

# 删除 MutatingWebhookConfiguration
kubectl delete mutatingwebhookconfiguration node-selector-webhook

# 删除 Deployment
kubectl delete deployment node-validation-webhook -n my-namespace

# 删除 Service
kubectl delete service webhook-service -n my-namespace

# 删除 RBAC
kubectl delete clusterrolebinding node-reader-binding
kubectl delete clusterrolebinding webhook-validator-binding
kubectl delete clusterrole node-reader
kubectl delete clusterrole webhook-validator
kubectl delete rolebinding pod-full-control-binding -n my-namespace
kubectl delete role pod-full-control -n my-namespace

# 删除 ServiceAccount
kubectl delete serviceaccount multi-node-operator-sa -n my-namespace
kubectl delete serviceaccount webhook-sa -n my-namespace

# 删除命名空间
kubectl delete namespace my-namespace

# 移除节点标签
kubectl label node hadoop02 allowed-node-
kubectl label node example.com227 allowed-node-
kubectl label node kg-lab-83-91 allowed-node-
```



------

## 🔐 安全说明

### 最小权限原则

- Webhook 只授予必要的 RBAC 权限
- ServiceAccount 只授予创建/删除 Pod 的权限
- Token 应妥善保管，不要泄露

### Token 管理

bash

```
# 查看 Token 是否存在
kubectl get secret -n my-namespace | grep multi-node-operator-sa

# 删除 Token（如果需要撤销）
kubectl delete secret <secret-name> -n my-namespace

# 重新创建 Token
kubectl delete serviceaccount multi-node-operator-sa -n my-namespace
kubectl apply -f 1-serviceaccount.yaml
```



------

## 🛠️ 自定义开发

### 修改允许的节点

bash

```
# 方式一：修改 Deployment 环境变量
kubectl set env deployment/node-validation-webhook -n my-namespace \
  ALLOWED_NODES="node-01,node-02,node-03"

# 方式二：编辑 Deployment
kubectl edit deployment node-validation-webhook -n my-namespace
```



### 修改 Webhook 逻辑

1. 编辑 `3-webhook-code-configmap.yaml`

2. 修改 Python 代码

3. 重新应用 ConfigMap：

   bash

   ```
   kubectl apply -f 3-webhook-code-configmap.yaml
   kubectl rollout restart deployment/node-validation-webhook -n my-namespace
   ```

   

### 构建自定义镜像

bash

```
# 1. 修改 Dockerfile
vim Dockerfile

# 2. 构建镜像
docker build -t webhook-node-validator:latest .

# 3. 推送镜像
docker push webhook-node-validator:latest

# 4. 更新 Deployment
kubectl rollout restart deployment/node-validation-webhook -n my-namespace
```



------

## 📊 性能指标

| 指标             | 值          |
| :--------------- | :---------- |
| Webhook 响应时间 | < 50ms      |
| 内存使用         | ~128Mi      |
| CPU 使用         | ~100m       |
| 副本数           | 2（高可用） |

------

## 📚 参考资料

- [Kubernetes Admission Webhooks](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)
- [ServiceAccount Tokens](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/)
- [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Namespace Selectors](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/#namespace-selectors)

