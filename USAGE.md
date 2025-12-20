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
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       └── service.yaml
├── product-service/
│   └── ...
└── ingress/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
        └── ingress.yaml
```

### Deploy User Service

```bash
cd traversium-helm-charts

# Initial deployment
helm install user-service ./user-service

# Watch deployment
kubectl get pods -w

# Check deployment status
kubectl get deployments
kubectl get pods
kubectl get services
```

### Deploy Ingress Controller

```bash
# Install nginx ingress controller (only once)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --set controller.service.externalTrafficPolicy=Local \
   --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

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
      --set auth.interBrokerProtocol=plaintext \
      --set controller.replicaCount=1 \
      --set controller.heapOpts="-Xmx512m -Xms512m" \
      --set controller.resources.requests.cpu="250m" \
      --set controller.resources.limits.cpu="500m" \
      --set controller.resources.requests.memory="1Gi" \
      --set controller.resources.limits.memory="1Gi"

# Verify Kafka is running
kubectl get pods -l app.kubernetes.io/name=kafka

# Check Kafka service
kubectl get svc kafka

To set kafka bootstrap server address for other services, use: kafka.kafka-test.svc.cluster.local:9092 where 'kafka-test' is the namespace.
```


**Note:** The Kafka service will be accessible at `kafka:9092` from within the cluster.

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
     --set resources.limits.memory="1Gi"
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

```bash
# Port-forward to access Kibana locally
kubectl port-forward -n monitoring svc/kibana-kibana 5601:5601
```

Then open http://localhost:5601 in your browser.

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

### Update Docker Image

#### Method 1: Update values.yaml (Recommended)

```bash
# Edit values.yaml
cd user-service
# Change image.tag: "1.0.1"

# Upgrade deployment
helm upgrade user-service ./user-service
```

#### Method 2: Command Line Override

```bash
helm upgrade user-service ./user-service \
  --set image.tag=1.0.1
```

#### Method 3: Force Pull Same Tag

If you updated the image but kept the same tag:

```bash
# Update values.yaml: pullPolicy: Always

# Or restart deployment
kubectl rollout restart deployment user-service
```

### Update Configuration

```bash
# Edit values.yaml with new config

# Upgrade deployment
helm upgrade user-service ./user-service

# Check rollout status
kubectl rollout status deployment user-service
```

### Update Secrets

```bash
# Delete old secret
kubectl delete secret neon-db-secret

# Create new secret
kubectl create secret generic neon-db-secret \
  --from-literal=url='NEW_URL' \
  --from-literal=username='NEW_USERNAME' \
  --from-literal=password='NEW_PASSWORD'

# Restart deployment to pick up new secret
kubectl rollout restart deployment user-service

# Example to create database secret for new service
majarazinger@Maja-Razinger-MacBook-Pro-M3 TraversiumHelmCharts % kubectl create secret generic neon-social-db-secret \
  --from-literal=url='jdbc:postgresql://' \
  --from-literal=username='NEW_USERNAME' \
  --from-literal=password='NEW_PASSWORD'
secret/neon-social-db-secret created
```

### Rollback Deployment

```bash
# View revision history
helm history user-service

# Rollback to previous version
helm rollback user-service

# Rollback to specific revision
helm rollback user-service 2
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
