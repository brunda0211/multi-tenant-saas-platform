#!/bin/bash
set -e

TENANT_ID=$1
DB_PASSWORD=${2:-"changeme123"}

if [ -z "$TENANT_ID" ]; then
  echo "Usage: ./provision-tenant.sh TENANT_ID [DB_PASSWORD]"
  echo "Example: ./provision-tenant.sh acme-corp mySecurePass123"
  exit 1
fi

echo "========================================="
echo "Provisioning tenant: $TENANT_ID"
echo "========================================="

# Step 1: Create namespace with quota
echo "✅ Creating namespace and resource quota..."
sed "s/{{TENANT_ID}}/$TENANT_ID/g" ../kubernetes/namespaces/tenant-template.yaml | kubectl apply -f -

# Step 2: Create database for tenant
echo "✅ Creating PostgreSQL database for tenant..."
RDS_ENDPOINT=$(cd ../terraform/rds && terraform output -raw rds_endpoint | cut -d: -f1)
DB_ADMIN_PASS="ChangeMe123!SecurePassword"

# Create database and user
kubectl run postgres-client-$TENANT_ID \
  --image=postgres:14 \
  --rm -i --restart=Never \
  --env="PGPASSWORD=$DB_ADMIN_PASS" \
  -- psql -h $RDS_ENDPOINT -U dbadmin -d multitenantdb -c "
    CREATE DATABASE ${TENANT_ID//-/_}_db;
    CREATE USER ${TENANT_ID//-/_}_user WITH PASSWORD '$DB_PASSWORD';
    GRANT ALL PRIVILEGES ON DATABASE ${TENANT_ID//-/_}_db TO ${TENANT_ID//-/_}_user;
  " 2>/dev/null || echo "Database may already exist"

# Step 3: Create database secret
echo "✅ Creating database credentials secret..."
kubectl create secret generic db-credentials \
  --from-literal=host=$RDS_ENDPOINT \
  --from-literal=port=5432 \
  --from-literal=database=${TENANT_ID//-/_}_db \
  --from-literal=username=${TENANT_ID//-/_}_user \
  --from-literal=password=$DB_PASSWORD \
  --namespace=tenant-$TENANT_ID \
  --dry-run=client -o yaml | kubectl apply -f -

# Step 4: Deploy sample application
echo "✅ Deploying sample application..."
cat <<YAML | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-$TENANT_ID
  namespace: tenant-$TENANT_ID
  labels:
    app: $TENANT_ID
    tenant: $TENANT_ID
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $TENANT_ID
  template:
    metadata:
      labels:
        app: $TENANT_ID
        tenant: $TENANT_ID
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        env:
        - name: TENANT_ID
          value: "$TENANT_ID"
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: host
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: database
---
apiVersion: v1
kind: Service
metadata:
  name: app-$TENANT_ID
  namespace: tenant-$TENANT_ID
  labels:
    app: $TENANT_ID
spec:
  type: NodePort
  selector:
    app: $TENANT_ID
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
YAML

# Step 5: Wait for deployment
echo "✅ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/app-$TENANT_ID -n tenant-$TENANT_ID

echo ""
echo "========================================="
echo "✅ Tenant $TENANT_ID provisioned successfully!"
echo "========================================="
echo ""
echo "Resources created:"
kubectl get all -n tenant-$TENANT_ID
echo ""
echo "Access URL: http://<node-ip>:<nodeport>"
echo "Get NodePort: kubectl get svc app-$TENANT_ID -n tenant-$TENANT_ID"
echo ""
