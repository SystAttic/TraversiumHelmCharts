# Traversium AKS Cluster Usage Guide

## Table of Contents
- [Prerequisites](#prerequisites)
- [Cluster Connection](#cluster-connection)
- [Secrets Management](#secrets-management)
- [Deployment](#deployment)
- [Accessing Services](#accessing-services)
- [Updating Services](#updating-services)
- [Cost Management](#cost-management)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

Please install azure-cli, kubectl, and helm on your local machine.

### Verify Installation

```bash
az --version
kubectl version --client
helm version
```

---

## Cluster Connection

### 1. Login to Azure

```bash
az login
```

### 2. Connect to AKS Cluster

```bash
az aks get-credentials \
  --name <name> \
  --resource-group <name-of-resource-group>
```

### 3. Verify Connection

```bash
# Check current context
kubectl config current-context
# Should show: <name>

# Check cluster nodes
kubectl get nodes
```

---

## Secrets Management

### GitHub Container Registry Secret

Required for pulling Docker images from GitHub Packages.

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_GITHUB_USERNAME \
  --docker-password=YOUR_GITHUB_TOKEN
```

**Get GitHub token:**
1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Generate token with `read:packages` scope

### Neon Database Secret

Database credentials for PostgreSQL.

```bash
kubectl create secret generic neon-db-secret \
  --from-literal=url='jdbc:postgresql://ep-empty-lake-xxx.neon.tech/neondb?sslmode=require' \
  --from-literal=username='neondb_owner' \
  --from-literal=password='YOUR_NEON_PASSWORD'
```

### Firebase Secret

Firebase service account credentials.

```bash
kubectl create secret generic firebase-secret \
  --from-file=traversium.json=/path/to/your/firebase-credentials.json
```

### View Existing Secrets

```bash
# List all secrets
kubectl get secrets

# View secret details (base64 encoded)
kubectl get secret neon-db-secret -o yaml

# Delete a secret (to recreate)
kubectl delete secret SECRET_NAME
```

---

## Deployment

### Project Structure

```
traversium-helm-charts/
├── user-service/
│   ├── Chart.yaml
│   ├── values.yaml          # Default/common configuration
│   ├── values-dev.yaml       # Development overrides
│   ├── values-prod.yaml      # Production overrides
│   └── templates/
│       ├── deployment.yaml
│       └── service.yaml
├── trip-service/
│   └── ...
└── ingress/
    ├── Chart.yaml
    ├── values.yaml
    ├── values-dev.yaml
    ├── values-prod.yaml
    └── templates/
        └── ingress.yaml
```

### Environment-Specific Deployments

Each service has three values files:
- **values.yaml**: Common configuration shared across all environments
- **values-dev.yaml**: Development-specific settings (lower resources, debug logging, `-dev` secrets/topics)
- **values-prod.yaml**: Production-specific settings (higher resources, multiple replicas, prod secrets)

### Deploy to Development

```bash
cd traversium-helm-charts

# Deploy user service to development
helm upgrade --install user-service ./user-service \
  -f ./user-service/values.yaml \
  -f ./user-service/values-dev.yaml \
  --namespace dev \
  --create-namespace

# Deploy all services to development
helm upgrade --install trip-service ./trip-service -f ./trip-service/values.yaml -f ./trip-service/values-dev.yaml -n dev --create-namespace
helm upgrade --install notification-service ./notification-service -f ./notification-service/values.yaml -f ./notification-service/values-dev.yaml -n dev --create-namespace
helm upgrade --install audit-service ./audit-service -f ./audit-service/values.yaml -f ./audit-service/values-dev.yaml -n dev --create-namespace
helm upgrade --install social-service ./social-service -f ./social-service/values.yaml -f ./social-service/values-dev.yaml -n dev --create-namespace
helm upgrade --install file-storage-service ./file-storage-service -f ./file-storage-service/values.yaml -f ./file-storage-service/values-dev.yaml -n dev --create-namespace
helm upgrade --install moderation-service ./moderation-service -f ./moderation-service/values.yaml -f ./moderation-service/values-dev.yaml -n dev --create-namespace

# Deploy ingress to development
helm upgrade --install ingress ./ingress -f ./ingress/values.yaml -f ./ingress/values-dev.yaml -n dev --create-namespace
```

### Deploy to Production

```bash
cd traversium-helm-charts

# Deploy user service to production
helm upgrade --install user-service ./user-service \
  -f ./user-service/values.yaml \
  -f ./user-service/values-prod.yaml \
  --namespace production \
  --create-namespace

# Deploy all services to production
helm upgrade --install trip-service ./trip-service -f ./trip-service/values.yaml -f ./trip-service/values-prod.yaml -n production --create-namespace
helm upgrade --install notification-service ./notification-service -f ./notification-service/values.yaml -f ./notification-service/values-prod.yaml -n production --create-namespace
helm upgrade --install audit-service ./audit-service -f ./audit-service/values.yaml -f ./audit-service/values-prod.yaml -n production --create-namespace
helm upgrade --install social-service ./social-service -f ./social-service/values.yaml -f ./social-service/values-prod.yaml -n production --create-namespace
helm upgrade --install file-storage-service ./file-storage-service -f ./file-storage-service/values.yaml -f ./file-storage-service/values-prod.yaml -n production --create-namespace
helm upgrade --install moderation-service ./moderation-service -f ./moderation-service/values.yaml -f ./moderation-service/values-prod.yaml -n production --create-namespace

# Deploy ingress to production
helm upgrade --install ingress ./ingress -f ./ingress/values.yaml -f ./ingress/values-prod.yaml -n production --create-namespace
```

### Check Deployment Status

```bash
# Watch deployment in specific namespace
kubectl get pods -n production -w

# Check all resources in production
kubectl get all -n production

# Check all resources in dev
kubectl get all -n dev

# View actual values used in deployment
helm get values user-service -n production
helm get values user-service -n dev
```

### Deploy Ingress Controller

```bash
# Install nginx ingress controller (only once)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
 helm install nginx-ingress ingress-nginx/ingress-nginx \
     --namespace production \
     --set controller.service.loadBalancerIP="20.240.93.121" \
     --set controller.service.externalTrafficPolicy=Local \
     --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-resource-group"="rg-aks-traversium-test-sweden" \
     --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \


# Deploy your ingress rules
helm install traversium-ingress ./ingress
```

### Deploy Kafka

Required for message queue communication between services.

```bash
# Add Bitnami repo if not already added
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install Kafka (it installs it in new namespace 'kafka-test')
# NUJNO 1 REPLICA COUNT K JE CLUSTRU ZMANKAL MEMORY (3je porabjo 1.5GB)
  helm install kafka oci://registry-1.docker.io/bitnamicharts/kafka \
      --version 32.0.1 \
      --namespace kafka-test \
      --create-namespace \
      --set image.registry=docker.io \
      --set image.repository=bitnamilegacy/kafka \
      --set image.tag=4.0.0-debian-12-r0 \
      --set global.security.allowInsecureImages=true \
      --set listeners.client.protocol=PLAINTEXT \
      --set listeners.controller.protocol=PLAINTEXT \
      --set auth.clientProtocol=plaintext \
      --set auth.interBrokerProtocol=plaintext

# Verify Kafka is running
kubectl get pods -l app.kubernetes.io/name=kafka

# Check Kafka service
kubectl get svc kafka

To set kafka bootstrap server address for other services, use: kafka.kafka-test.svc.cluster.local:9092 where 'kafka-test' is the namespace.
```


**Note:** The Kafka service will be accessible at `kafka:9092` from within the cluster.

### Deploy Keycloak

Keycloak provides authentication and authorization (OAuth2/OIDC) for the microservices.

```bash
# Update Helm dependencies for Keycloak chart
cd keycloak
helm dependency update
cd ..

# Install Keycloak in dev namespace
helm upgrade --install keycloak ./keycloak \
  -f ./keycloak/values.yaml \
  -f ./keycloak/values-dev.yaml \
  --namespace dev \
  --create-namespace

# Verify Keycloak is running
kubectl get pods -n dev | grep keycloak
kubectl get svc -n dev | grep keycloak
```

#### Access Keycloak Admin Console

```bash
# Port-forward to access Keycloak locally
kubectl port-forward -n dev svc/keycloak-http 8080:8080

# Open http://localhost:8080/auth
# Username: admin
# Password: admin (from keycloak-admin-secret-dev)
```

#### Configure Keycloak Realm and Clients

After Keycloak is running, you need to manually configure the realm and clients:

1. **Create Realm:**
   - Login to Keycloak Admin Console (http://localhost:8080/auth)
   - Click **Create Realm**
   - Name: `traversium`
   - Click **Create**

2. **Create OAuth2 Client for user-service:**
   - Go to **Clients** → **Create client**
   - Client ID: `user-service`
   - Client type: OpenID Connect
   - Click **Next**
   - Client authentication: **ON**
   - Service accounts roles: **ON**
   - Click **Save**
   - Go to **Credentials** tab
   - Copy the **Client secret**
   - Update the development secret (if different from default):
     ```bash
     kubectl delete secret keycloak-client-secret -n dev
     kubectl create secret generic keycloak-client-secret \
       --from-literal=client-secret='<your-copied-secret>' \
       -n dev
     ```

3. **Create OAuth2 Client for trip-service:**
   - Repeat above steps with Client ID: `trip-service`
   - Update secret:
     ```bash
     kubectl delete secret keycloak-trip-client-secret -n dev
     kubectl create secret generic keycloak-trip-client-secret \
       --from-literal=client-secret='<your-copied-secret>' \
       -n dev
     ```

4. **Create OAuth2 Client for social-service:**
   - Repeat above steps with Client ID: `social-service`
   - Update secret:
     ```bash
     kubectl delete secret keycloak-social-client-secret -n dev
     kubectl create secret generic keycloak-social-client-secret \
       --from-literal=client-secret='<your-copied-secret>' \
       -n dev
     ```

5. **Create OAuth2 Resource Server for moderation-service:**
   - Create client with Client ID: `moderation-service`
   - Client authentication: **ON**
   - Authorization: **ON**

6. **Update Service Configuration:**
   - Edit values-dev.yaml files to add token URI:

   For user-service, trip-service, social-service:
   ```yaml
   security:
     oauth2:
       client:
         tokenUri: "http://keycloak-http.dev.svc.cluster.local:8080/auth/realms/traversium/protocol/openid-connect/token"
   ```

   For moderation-service:
   ```yaml
   security:
     oauth2:
       resourceserver:
         jwt:
           issuerUri: "http://keycloak-http.dev.svc.cluster.local:8080/auth/realms/traversium"
   ```

7. **Redeploy affected services** to pick up the Keycloak configuration:
   ```bash
   helm upgrade user-service ./user-service -f ./user-service/values.yaml -f ./user-service/values-dev.yaml -n dev
   helm upgrade trip-service ./trip-service -f ./trip-service/values.yaml -f ./trip-service/values-dev.yaml -n dev
   helm upgrade social-service ./social-service -f ./social-service/values.yaml -f ./social-service/values-dev.yaml -n dev
   helm upgrade moderation-service ./moderation-service -f ./moderation-service/values.yaml -f ./moderation-service/values-dev.yaml -n dev
   ```

### Deploy Prometheus

Prometheus is used for monitoring and metrics collection from all services.

```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install Prometheus in monitoring namespace
helm install prometheus prometheus-community/prometheus --namespace monitoring

# Verify Prometheus is running
kubectl get pods -n monitoring
```

### Access Prometheus UI

```bash
# Port-forward to access Prometheus UI locally
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

Then open http://localhost:9090 in your browser.

**To verify services are being scraped:**
- Go to Status → Targets in the Prometheus UI
- Look for the `kubernetes-pods` job
- All your services should be listed and showing as "UP"

### Deploy Grafana

Grafana is used for visualizing metrics from Prometheus.

```bash
# Install Grafana in monitoring namespace
helm install grafana grafana/grafana \
     --namespace monitoring \
     --reuse-values \
     --set 'grafana\.ini'.server.root_url="http://<public_ip>/grafana" \
     --set 'grafana\.ini'.server.serve_from_sub_path=true

# Verify Grafana is running
kubectl get pods -n monitoring | grep grafana
```

### Access Grafana

**Get admin password:**
```bash
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

**Port-forward to access locally:**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
```

Then open http://localhost:3000 in your browser.
- Username: `admin`
- Password: (from command above)

### Configure Prometheus Data Source in Grafana

1. Login to Grafana
2. Go to **Connections** → **Data Sources** → **Add data source**
3. Select **Prometheus**
4. Configure:
   - **Name**: Prometheus
   - **URL**: `http://prometheus-server`
   - **Access**: Server (default)
5. Click **Save & Test** - should see "Data source is working"

### Import Dashboards

Import pre-built dashboards for monitoring:

1. Go to **Dashboards** → **Import**
2. Enter dashboard ID:
   - **Kubernetes Cluster**: `315` (for Kubernetes monitoring)
3. Select **Prometheus** as data source
4. Click **Import**

---

## Deploy ELK Stack (Elasticsearch, Logstash, Kibana)

ELK stack is used for centralized logging and log analysis.

### Add Elastic Helm Repository

```bash
# Add the Elastic Helm repository
helm repo add elastic https://helm.elastic.co
helm repo update
```

### Install Elasticsearch

```bash
# Install Elasticsearch in monitoring namespace (traja neki časa)
 helm install elasticsearch elastic/elasticsearch \
       --namespace efk \
       --set replicas=1 \
       --set esJavaOpts="-Xms1g -Xmx1g" \
       --set resources.requests.cpu="250m" \
       --set resources.limits.cpu="500m" \
       --set resources.requests.memory="2Gi" \
       --set resources.limits.memory="2Gi" \
       --set clusterHealthCheckParams="wait_for_status=yellow&timeout=60s" \
       --set minimumMasterNodes=1

# Verify Elasticsearch is running
kubectl get pods -n monitoring | grep elasticsearch

# Delete Logs after 1 day so index doesn't grow too much
 kubectl exec elasticsearch-master-0 -n efk -- curl -s -k -u elastic:gCE07s2Ab76r2AyF -X PUT 'https://localhost:9200/_ilm/policy/fluentbit-cleanup-policy' -H 'Content-Type: application/json' -d '{
    "policy": {
      "phases": {
        "delete": {
          "min_age": "1d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'
```
### Install Kibana

```bash
# Install Kibana in monitoring namespace (2 minuti)
helm install kibana elastic/kibana \
  --namespace efk \
  --set elasticsearchHosts="https://elasticsearch-master:9200" \
  --set resources.requests.cpu="250m" \
  --set resources.limits.cpu="500m" \
  --set resources.requests.memory="512Mi" \
  --set resources.limits.memory="1Gi" \
  --set kibanaConfig."xpack\.encryptedSavedObjects\.encryptionKey"="zF6nL9vB8qP2rX0tV3mY5cJ7sH1kW8dA"

# Verify Kibana is running
kubectl get pods -n monitoring | grep kibana
```

### Install Fluent Bit (Log Collection)

```bash
# Add Fluent Helm repository
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

# Install Fluent Bit as DaemonSet (runs on each node)
helm install fluent-bit fluent/fluent-bit \
     --namespace efk \
     -f efk/fluent-bit-values.yaml

# Verify Fluent Bit is running
kubectl get pods -n monitoring | grep fluent-bit
```

### Access Kibana UI

**Option 1: Port Forwarding (Quick Access)**
```bash
# Port-forward to access Kibana locally
kubectl port-forward -n efk-prod svc/kibana-kibana 5601:5601
```

Then open http://localhost:5601 in your browser.

**Option 2: Ingress (Production Access)**

Deploy the Kibana Ingress to expose Kibana through the nginx ingress controller:

```bash
# Apply the Kibana ingress to production namespace
kubectl apply -f efk/kibana-ingress.yaml -n efk-prod
```

After deploying the ingress, Kibana will be accessible at:
```
http://<INGRESS-IP>/
```

To get the Ingress IP:
```bash
kubectl get svc nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Note:** The ingress configuration in `efk/kibana-ingress.yaml` routes traffic on path `/` to the Kibana service on port 5601.

### Configure Kibana

1. Open Kibana at http://localhost:5601
2. Go to **Management** → **Stack Management** → **Index Patterns**
3. Create index pattern: `fluentbit-*`
4. Select `@timestamp` as the time field
5. Go to **Discover** to view your logs

username: `elastic`

geslo:
```bash
kubectl get secret elasticsearch-master-credentials -n efk -o jsonpath="{.data.password}" | base64 --decode ; echo 
```

### Verify ELK Stack

```bash
# Check all ELK pods are running
kubectl get pods -n monitoring | grep -E 'elasticsearch|kibana|fluent-bit'

# Check Elasticsearch health
kubectl exec -n monitoring elasticsearch-master-0 -- curl -s http://localhost:9200/_cluster/health?pretty

# View Fluent Bit logs
kubectl logs -n monitoring -l app.kubernetes.io/name=fluent-bit --tail=50
```

---

## Accessing Services

### Get Service URLs

```bash
# For Ingress (multiple services)
kubectl get ingress traversium-ingress
# Or get nginx controller IP
kubectl get svc nginx-ingress-ingress-nginx-controller
```

### Access Endpoints

**With Ingress:**
```
http://<INGRESS-IP>/users/swagger-ui.html
http://<INGRESS-IP>/users/rest/v1/users
http://<INGRESS-IP>/products/rest/v1/products
```

### View Logs

```bash
# Get pod name
kubectl get pods

# View logs
kubectl logs user-service-XXXXX

# Follow logs (stream)
kubectl logs -f user-service-XXXXX

# View logs for all pods with label
kubectl logs -l app=user-service
```

---

## Updating Services

### Update Configuration

```bash
helm upgrade user-service ./user-service \
  -f values.yaml \
  -f values-prod.yaml \
  -n production

# Check rollout status
kubectl rollout status deployment user-service -n production
```

### Update Secrets

When using environment-specific deployments, create separate secrets for each environment:

```bash
# Development secrets (in dev namespace)
kubectl create secret generic neon-user-db-secret-dev \
  --from-literal=url='jdbc:postgresql://dev-db.neon.tech/neondb?sslmode=require' \
  --from-literal=username='dev_user' \
  --from-literal=password='DEV_PASSWORD' \
  -n dev

kubectl create secret generic firebase-secret-dev \
  --from-file=traversium.json=/path/to/firebase-dev-credentials.json \
  -n dev

# Production secrets (in production namespace)
kubectl create secret generic neon-user-db-secret-prod \
  --from-literal=url='jdbc:postgresql://prod-db.neon.tech/neondb?sslmode=require' \
  --from-literal=username='prod_user' \
  --from-literal=password='PROD_PASSWORD' \
  -n production

kubectl create secret generic firebase-secret-prod \
  --from-file=traversium.json=/path/to/firebase-prod-credentials.json \
  -n production

# Update existing secret
kubectl delete secret neon-user-db-secret-dev -n dev
kubectl create secret generic neon-user-db-secret-dev \
  --from-literal=url='NEW_URL' \
  --from-literal=username='NEW_USERNAME' \
  --from-literal=password='NEW_PASSWORD' \
  -n dev

# Restart deployment to pick up new secret
kubectl rollout restart deployment user-service -n dev
```

### Rollback Deployment

```bash
# View revision history for specific environment
helm history user-service -n production
helm history user-service -n dev

# Rollback to previous version
helm rollback user-service -n production
helm rollback user-service -n dev

# Rollback to specific revision
helm rollback user-service 2 -n production
```

---

## Cost Management

### Stop Cluster

When not actively using the cluster:

```bash
# Stop cluster (keeps all data, no compute charges)
az aks stop \
  --name aks-test-traversium \
  --resource-group rg-aks-traversium-test-sweden
```

**Cost while stopped:** ~$1-2/month (storage only)

### Start Cluster

```bash
# Start cluster (takes 3-5 minutes)
az aks start \
  --name aks-test-traversium \
  --resource-group rg-aks-traversium-test-sweden

# Reconnect kubectl
az aks get-credentials \
  --name aks-test-traversium \
  --resource-group rg-aks-traversium-test-sweden

# Verify cluster is running
kubectl get nodes
```

### Check Cluster Status

```bash
az aks show \
  --name aks-test-traversium \
  --resource-group rg-aks-traversium-test-sweden \
  --query powerState
```

### Delete Everything (When Done)

```bash
# Delete entire resource group (removes cluster and all resources)
az group delete \
  --name rg-aks-traversium-test-sweden \
  --yes
```

### Neon Database (Auto-suspends)

- Neon automatically suspends after 5 minutes of inactivity
- Free tier: 100 compute hours/month
- Monitor usage: https://console.neon.tech

---

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods

# Describe pod for events
kubectl describe pod user-service-XXXXX

# Check logs
kubectl logs user-service-XXXXX

# Check previous logs if pod crashed
kubectl logs user-service-XXXXX --previous
```

### Image Pull Errors

```bash
# Check if secret exists
kubectl get secret ghcr-secret

# Recreate secret with correct credentials
kubectl delete secret ghcr-secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_TOKEN

# Restart deployment
kubectl rollout restart deployment user-service
```

### Database Connection Errors

```bash
# Check if secret exists
kubectl get secret neon-db-secret

# Verify secret contents
kubectl get secret neon-db-secret -o jsonpath='{.data.url}' | base64 -d

# Common issues:
# - Missing "jdbc:" prefix in URL
# - Wrong username/password
# - Neon database suspended (check Neon console)

# Test connection from pod
kubectl exec -it user-service-XXXXX -- curl http://localhost:8090/actuator/health
```

### Service Not Accessible

```bash
# Check service exists
kubectl get svc

# For LoadBalancer - wait for EXTERNAL-IP
kubectl get svc user-service -w

# For Ingress - check ingress status
kubectl get ingress
kubectl describe ingress traversium-ingress

# Check if nginx ingress controller is running
kubectl get pods -n default | grep nginx
```

### Common Commands

```bash
# Get all resources
kubectl get all

# Delete pod (will be recreated by deployment)
kubectl delete pod user-service-XXXXX

# Scale deployment
kubectl scale deployment user-service --replicas=2

# Execute command in pod
kubectl exec -it user-service-XXXXX -- /bin/sh

# Port forward to local machine
kubectl port-forward svc/user-service 8080:80
```
### To test Liveness and Readiness Probes

```bash
 kubectl port-forward deployment/file-storage-service 8095:8095

curl http://localhost:8095/files/actuator/health/liveness
curl http://localhost:8095/files/actuator/health/readiness
```

And to see that kubernetes is usng them (for example user-service):

```bash
kubectl describe deployment user-service

or with events:
kubectl get events --sort-by='.lastTimestamp' | grep user-service | grep -E 'Liveness|Readiness|Unhealthy|probe' | tail -20
```
