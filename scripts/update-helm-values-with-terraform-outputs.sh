#!/bin/bash

# Update Helm Chart Values with Terraform Infrastructure Outputs
# This script updates ArgoCD Helm charts with real infrastructure values from Terraform

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/sample-devops-agent-eks-workshop/terraform/eks/default"
HELM_CHARTS_DIR="${SCRIPT_DIR}/sample-devops-agent-eks-workshop/helm-charts"

echo "=========================================="
echo "Updating Helm Charts with Terraform Outputs"
echo "=========================================="
echo ""

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "❌ Error: Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

# Check if helm-charts directory exists
if [ ! -d "$HELM_CHARTS_DIR" ]; then
    echo "❌ Error: Helm charts directory not found: $HELM_CHARTS_DIR"
    exit 1
fi

# Get Terraform outputs
echo "📊 Fetching Terraform outputs..."
cd "$TERRAFORM_DIR"

# Export outputs as environment variables
export CATALOG_DB_ENDPOINT=$(terraform output -raw catalog_db_endpoint)
export CATALOG_DB_PORT=$(terraform output -raw catalog_db_port)
export CATALOG_DB_USERNAME=$(terraform output -raw catalog_db_username)
export CATALOG_DB_PASSWORD=$(terraform output -raw catalog_db_password)
export CATALOG_DB_NAME=$(terraform output -raw catalog_db_name)

export CARTS_DYNAMODB_TABLE=$(terraform output -raw carts_dynamodb_table_name)
export CARTS_IAM_ROLE_ARN=$(terraform output -raw carts_iam_role_arn)

export ORDERS_DB_ENDPOINT=$(terraform output -raw orders_db_endpoint)
export ORDERS_DB_PORT=$(terraform output -raw orders_db_port)
export ORDERS_DB_USERNAME=$(terraform output -raw orders_db_username)
export ORDERS_DB_PASSWORD=$(terraform output -raw orders_db_password)
export ORDERS_DB_NAME=$(terraform output -raw orders_db_name)

export MQ_BROKER_ENDPOINT=$(terraform output -raw mq_broker_endpoint)
export MQ_USERNAME=$(terraform output -raw mq_username)
export MQ_PASSWORD=$(terraform output -raw mq_password)

export CHECKOUT_REDIS_ENDPOINT=$(terraform output -raw checkout_elasticache_endpoint)
export CHECKOUT_REDIS_PORT=$(terraform output -raw checkout_elasticache_port)

echo "✅ Terraform outputs fetched successfully"
echo ""

# ============================================================================
# Update Catalog Helm Chart
# ============================================================================

echo "📝 Updating catalog/values.yaml..."
cat > "${HELM_CHARTS_DIR}/catalog/values.yaml" << 'EOF'
# Default values for catalog.
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 2

image:
  repository: public.ecr.aws/aws-containers/retail-store-sample-catalog
  pullPolicy: IfNotPresent
  tag: 

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}

podSecurityContext:
  fsGroup: 1000

securityContext:
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    memory: 256Mi
  requests:
    cpu: 256m
    memory: 256Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []

metrics:
  enabled: true
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"

configMap:
  create: true
  name:

app:
  persistence:
    provider: mysql
    endpoint: "CATALOG_DB_ENDPOINT_PLACEHOLDER:CATALOG_DB_PORT_PLACEHOLDER"
    database: "CATALOG_DB_NAME_PLACEHOLDER"

    secret:
      create: true
      name: catalog-db
      username: CATALOG_DB_USERNAME_PLACEHOLDER
      password: "CATALOG_DB_PASSWORD_PLACEHOLDER"

mysql:
  create: false

securityGroups:
  create: false
  securityGroupIds: []

opentelemetry:
  enabled: false
  instrumentation: ""

podDisruptionBudget:
  enabled: false
  minAvailable: 2
  maxUnavailable: 1
EOF

# Replace placeholders with actual values
sed -i.bak "s|CATALOG_DB_ENDPOINT_PLACEHOLDER|${CATALOG_DB_ENDPOINT}|g" "${HELM_CHARTS_DIR}/catalog/values.yaml"
sed -i.bak "s|CATALOG_DB_PORT_PLACEHOLDER|${CATALOG_DB_PORT}|g" "${HELM_CHARTS_DIR}/catalog/values.yaml"
sed -i.bak "s|CATALOG_DB_NAME_PLACEHOLDER|${CATALOG_DB_NAME}|g" "${HELM_CHARTS_DIR}/catalog/values.yaml"
sed -i.bak "s|CATALOG_DB_USERNAME_PLACEHOLDER|${CATALOG_DB_USERNAME}|g" "${HELM_CHARTS_DIR}/catalog/values.yaml"
sed -i.bak "s|CATALOG_DB_PASSWORD_PLACEHOLDER|${CATALOG_DB_PASSWORD}|g" "${HELM_CHARTS_DIR}/catalog/values.yaml"
rm "${HELM_CHARTS_DIR}/catalog/values.yaml.bak"

echo "✅ catalog/values.yaml updated"

# ============================================================================
# Update Carts Helm Chart
# ============================================================================

echo "📝 Updating carts/values.yaml..."
cat > "${HELM_CHARTS_DIR}/carts/values.yaml" << 'EOF'
# Default values for carts.
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 2

image:
  repository: public.ecr.aws/aws-containers/retail-store-sample-cart
  pullPolicy: IfNotPresent
  tag: 

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: CARTS_IAM_ROLE_ARN_PLACEHOLDER
  name: ""

podAnnotations: {}

podSecurityContext:
  fsGroup: 1000

securityContext:
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    memory: 512Mi
  requests:
    cpu: 256m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []

metrics:
  enabled: true
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/actuator/prometheus"

configMap:
  create: true
  name:

app:
  persistence:
    provider: dynamodb
    dynamodb:
      tableName: CARTS_DYNAMODB_TABLE_PLACEHOLDER
      createTable: false

dynamodb:
  create: false

opentelemetry:
  enabled: false
  instrumentation: ""

podDisruptionBudget:
  enabled: false
  minAvailable: 2
  maxUnavailable: 1
EOF

# Replace placeholders
sed -i.bak "s|CARTS_IAM_ROLE_ARN_PLACEHOLDER|${CARTS_IAM_ROLE_ARN}|g" "${HELM_CHARTS_DIR}/carts/values.yaml"
sed -i.bak "s|CARTS_DYNAMODB_TABLE_PLACEHOLDER|${CARTS_DYNAMODB_TABLE}|g" "${HELM_CHARTS_DIR}/carts/values.yaml"
rm "${HELM_CHARTS_DIR}/carts/values.yaml.bak"

echo "✅ carts/values.yaml updated"

# ============================================================================
# Update Orders Helm Chart
# ============================================================================

echo "📝 Updating orders/values.yaml..."
cat > "${HELM_CHARTS_DIR}/orders/values.yaml" << 'EOF'
# Default values for orders.
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 2

image:
  repository: public.ecr.aws/aws-containers/retail-store-sample-orders
  pullPolicy: IfNotPresent
  tag: 

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}

podSecurityContext:
  fsGroup: 1000

securityContext:
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    memory: 512Mi
  requests:
    cpu: 256m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []

metrics:
  enabled: true
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/actuator/prometheus"

configMap:
  create: true
  name:

app:
  persistence:
    provider: 'postgres'
    endpoint: 'ORDERS_DB_ENDPOINT_PLACEHOLDER:ORDERS_DB_PORT_PLACEHOLDER'
    database: 'ORDERS_DB_NAME_PLACEHOLDER'

    secret:
      create: true
      name: orders-db
      username: ORDERS_DB_USERNAME_PLACEHOLDER
      password: "ORDERS_DB_PASSWORD_PLACEHOLDER"

  messaging:
    provider: 'rabbitmq'

    rabbitmq:
      addresses: ["MQ_BROKER_ENDPOINT_PLACEHOLDER"]

      secret:
        create: true
        name: orders-rabbitmq
        username: MQ_USERNAME_PLACEHOLDER
        password: "MQ_PASSWORD_PLACEHOLDER"

postgresql:
  create: false

rabbitmq:
  create: false

securityGroups:
  create: false
  securityGroupIds: []

opentelemetry:
  enabled: false
  instrumentation: ""

podDisruptionBudget:
  enabled: false
  minAvailable: 2
  maxUnavailable: 1
EOF

# Replace placeholders
sed -i.bak "s|ORDERS_DB_ENDPOINT_PLACEHOLDER|${ORDERS_DB_ENDPOINT}|g" "${HELM_CHARTS_DIR}/orders/values.yaml"
sed -i.bak "s|ORDERS_DB_PORT_PLACEHOLDER|${ORDERS_DB_PORT}|g" "${HELM_CHARTS_DIR}/orders/values.yaml"
sed -i.bak "s|ORDERS_DB_NAME_PLACEHOLDER|${ORDERS_DB_NAME}|g" "${HELM_CHARTS_DIR}/orders/values.yaml"
sed -i.bak "s|ORDERS_DB_USERNAME_PLACEHOLDER|${ORDERS_DB_USERNAME}|g" "${HELM_CHARTS_DIR}/orders/values.yaml"
sed -i.bak "s|ORDERS_DB_PASSWORD_PLACEHOLDER|${ORDERS_DB_PASSWORD}|g" "${HELM_CHARTS_DIR}/orders/values.yaml"
sed -i.bak "s|MQ_BROKER_ENDPOINT_PLACEHOLDER|${MQ_BROKER_ENDPOINT}|g" "${HELM_CHARTS_DIR}/orders/values.yaml"
sed -i.bak "s|MQ_USERNAME_PLACEHOLDER|${MQ_USERNAME}|g" "${HELM_CHARTS_DIR}/orders/values.yaml"
sed -i.bak "s|MQ_PASSWORD_PLACEHOLDER|${MQ_PASSWORD}|g" "${HELM_CHARTS_DIR}/orders/values.yaml"
rm "${HELM_CHARTS_DIR}/orders/values.yaml.bak"

echo "✅ orders/values.yaml updated"

# ============================================================================
# Update Checkout Helm Chart
# ============================================================================

echo "📝 Updating checkout/values.yaml..."
# Read existing checkout values and update only the Redis configuration
cat > "${HELM_CHARTS_DIR}/checkout/values.yaml" << 'EOF'
# Default values for checkout.
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 2

image:
  repository: public.ecr.aws/aws-containers/retail-store-sample-checkout
  pullPolicy: IfNotPresent
  tag: 

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}

podSecurityContext:
  fsGroup: 1000

securityContext:
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false
  runAsNonRoot: true
  runAsUser: 1000

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    memory: 512Mi
  requests:
    cpu: 256m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []

metrics:
  enabled: true
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/actuator/prometheus"

configMap:
  create: true
  name:

app:
  endpoints: {}
  redis:
    enabled: true
    host: CHECKOUT_REDIS_ENDPOINT_PLACEHOLDER
    port: CHECKOUT_REDIS_PORT_PLACEHOLDER

redis:
  create: false

securityGroups:
  create: false
  securityGroupIds: []

opentelemetry:
  enabled: false
  instrumentation: ""

podDisruptionBudget:
  enabled: false
  minAvailable: 2
  maxUnavailable: 1
EOF

# Replace placeholders
sed -i.bak "s|CHECKOUT_REDIS_ENDPOINT_PLACEHOLDER|${CHECKOUT_REDIS_ENDPOINT}|g" "${HELM_CHARTS_DIR}/checkout/values.yaml"
sed -i.bak "s|CHECKOUT_REDIS_PORT_PLACEHOLDER|${CHECKOUT_REDIS_PORT}|g" "${HELM_CHARTS_DIR}/checkout/values.yaml"
rm "${HELM_CHARTS_DIR}/checkout/values.yaml.bak"

echo "✅ checkout/values.yaml updated"

# ============================================================================
# Update UI Helm Chart
# ============================================================================

echo "📝 Updating ui/values.yaml..."
cat > "${HELM_CHARTS_DIR}/ui/values.yaml" << 'EOF'
# Default values for ui.
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

replicaCount: 2

image:
  repository: public.ecr.aws/aws-containers/retail-store-sample-ui
  pullPolicy: IfNotPresent
  tag: 

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}

podSecurityContext:
  fsGroup: 1000

securityContext:
  capabilities:
    drop:
      - ALL
    add:
      - NET_BIND_SERVICE
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    memory: 512Mi
  requests:
    cpu: 128m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 50

nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []

metrics:
  enabled: true
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/actuator/prometheus"

configMap:
  create: true
  name:

app:
  endpoints:
    catalog: http://retail-catalog.catalog.svc:80
    carts: http://retail-carts.carts.svc:80
    orders: http://retail-orders.orders.svc:80
    checkout: http://retail-checkout.checkout.svc:80
  chat:
    enabled: false

ingress:
  enabled: false

ingresses: []

istio:
  enabled: false

opentelemetry:
  enabled: false
  instrumentation: ""

podDisruptionBudget:
  enabled: false
  minAvailable: 2
  maxUnavailable: 1
EOF

echo "✅ ui/values.yaml updated"

echo ""
echo "=========================================="
echo "✅ All Helm charts updated successfully!"
echo "=========================================="
echo ""
echo "📋 Summary of changes:"
echo "  - catalog: MySQL RDS endpoint configured"
echo "  - carts: DynamoDB table and IAM role configured"
echo "  - orders: PostgreSQL RDS and RabbitMQ configured"
echo "  - checkout: ElastiCache Redis configured"
echo "  - ui: Service endpoints updated to retail-* services"
echo ""
echo "🔄 Next steps:"
echo "  1. Review the changes: git diff helm-charts/"
echo "  2. Commit: git add helm-charts/*/values.yaml"
echo "  3. Commit: git commit -m 'Configure Helm charts with Terraform infrastructure'"
echo "  4. Push: git push origin main"
echo "  5. Sync ArgoCD: argocd app sync retail-catalog retail-carts retail-orders retail-checkout retail-ui"
echo ""
