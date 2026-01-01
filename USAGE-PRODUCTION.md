# Production Deployment Guide

Complete guide for deploying the Traversium application to production on Kubernetes.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Create Production Secrets](#create-production-secrets)
3. [Deploy Infrastructure](#deploy-infrastructure)
4. [Deploy Application Services](#deploy-application-services)
5. [Verify Deployment](#verify-deployment)
6. [Access Services](#access-services)
7. [Troubleshooting](#troubleshooting)
8. [Updating Services](#updating-services)
9. [Cleanup](#cleanup)

---

## Prerequisites

Ensure you are connected to your Kubernetes cluster and have the production namespace ready:

```bash
# Connect to cluster
az aks get-credentials \
  --name <your-cluster-name> \
  --resource-group <your-resource-group>

# Verify connection
kubectl config current-context
kubectl get nodes

# Create production namespace
kubectl create namespace production
```

---

## Create Production Secrets

### Step 1: Run the Production Secrets Script - Ask Maja to send it to you if you don't have it

```bash
# Make script executable (if not already)
chmod +x create-production-secrets.sh

# Run the script to create all secrets
./create-production-secrets.sh
```

This will create:
- GitHub Container Registry secret (`ghcr-secret`)
- Database secrets for all services (user, trip, audit, social, notification)
- Firebase secret
- Azure Moderation secret
- Azure Storage secret

### Step 2: Verify Secrets

```bash
kubectl get secrets -n production
```

You should see all secrets listed:
```
NAME                              TYPE                             DATA   AGE
ghcr-secret                       kubernetes.io/dockerconfigjson   1      1m
neon-user-db-secret-prod          Opaque                           3      1m
neon-trip-db-secret-prod          Opaque                           3      1m
neon-audit-db-secret-prod         Opaque                           3      1m
neon-social-db-secret-prod        Opaque                           3      1m
neon-notification-db-secret-prod  Opaque                           3      1m
firebase-secret-prod              Opaque                           1      1m
azure-moderation-secret-prod      Opaque                           1      1m
azure-storage-secret-prod         Opaque                           1      1m
```

---

## Deploy Infrastructure

Deploy monitoring, logging, and messaging infrastructure before deploying application services.

### 1. Deploy Kafka

```bash
# Add Bitnami repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create Kafka namespace
kubectl create namespace kafka-prod

# Install Kafka (production configuration)
helm install kafka oci://registry-1.docker.io/bitnamicharts/kafka \
    --version 32.0.1 \
    --namespace kafka-prod \
    --set image.registry=docker.io \
    --set image.repository=bitnamilegacy/kafka \
    --set image.tag=4.0.0-debian-12-r0 \
    --set global.security.allowInsecureImages=true \
    --set listeners.client.protocol=PLAINTEXT \
    --set listeners.controller.protocol=PLAINTEXT \
    --set auth.clientProtocol=plaintext \
    --set auth.interBrokerProtocol=plaintext \
    --set controller.resourcesPreset=none \
    --set controller.resources.requests.cpu=250m \
    --set controller.resources.requests.memory=512Mi \
    --set controller.resources.limits.cpu=500m \
    --set controller.resources.limits.memory=1Gi


# Verify Kafka is running
kubectl get pods -n kafka-prod
kubectl get svc -n kafka-prod
```

**Kafka Bootstrap Server:** `kafka.kafka-prod.svc.cluster.local:9092`

### 2. Deploy Keycloak

Keycloak provides authentication and authorization (OAuth2/OIDC) for the microservices.

```bash
# Update Helm dependencies for Keycloak chart
cd keycloak
helm dependency update
cd ..

# Deploy Keycloak to production namespace
helm upgrade --install keycloak ./keycloak \
  -f ./keycloak/values.yaml \
  -f ./keycloak/values-prod.yaml \
  --namespace production

# Verify Keycloak is running
kubectl get pods -n production | grep keycloak
kubectl get svc -n production | grep keycloak
```

#### Access Keycloak Admin Console

**Option 1: Port Forwarding (for setup)**
```bash
# Port-forward to access Keycloak locally
kubectl port-forward -n production svc/keycloak-http 8080:8080

# Open http://localhost:8080/auth
# Username: admin
# Password: (from keycloak-admin-secret-prod)
```

**Option 2: Through Ingress**
```
# Keycloak is exposed via ingress at:
http://<EXTERNAL-IP>/auth

# Get external IP:
kubectl get svc -n production nginx-ingress-ingress-nginx-controller
```

#### Configure Keycloak Realm and Clients

After Keycloak is running, configure the realm and OAuth2 clients:

1. **Create Realm:**
   - Login to Keycloak Admin Console
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
   - **Important:** This secret should match what's in `create-production-secrets.sh`
   - If different, update the production secret:
     ```bash
     kubectl delete secret keycloak-client-secret-prod -n production
     kubectl create secret generic keycloak-client-secret-prod \
       --from-literal=client-secret='<your-client-secret>' \
       -n production
     ```

3. **Create OAuth2 Client for trip-service:**
   - Client ID: `trip-service`
   - Follow same steps as user-service
   - Update secret if needed:
     ```bash
     kubectl delete secret keycloak-trip-client-secret-prod -n production
     kubectl create secret generic keycloak-trip-client-secret-prod \
       --from-literal=client-secret='<your-client-secret>' \
       -n production
     ```

4. **Create OAuth2 Client for social-service:**
   - Client ID: `social-service`
   - Follow same steps as user-service
   - Update secret if needed:
     ```bash
     kubectl delete secret keycloak-social-client-secret-prod -n production
     kubectl create secret generic keycloak-social-client-secret-prod \
       --from-literal=client-secret='<your-client-secret>' \
       -n production
     ```

5. **Create OAuth2 Resource Server for moderation-service:**
   - Create client with Client ID: `moderation-service`
   - Client authentication: **ON**
   - Authorization: **ON**
   - Direct access grants: **ON** (for testing)

6. **Verify Token URIs in Service Configuration:**

   The following token URIs should already be configured in values-prod.yaml:

   For user-service, trip-service, social-service:
   ```yaml
   security:
     oauth2:
       client:
         tokenUri: "http://keycloak-http.production.svc.cluster.local:8080/auth/realms/traversium/protocol/openid-connect/token"
   ```

   For moderation-service:
   ```yaml
   security:
     oauth2:
       resourceserver:
         jwt:
           issuerUri: "http://keycloak-http.production.svc.cluster.local:8080/auth/realms/traversium"
   ```

7. **Redeploy Services** if you updated any secrets:
   ```bash
   kubectl rollout restart deployment user-service -n production
   kubectl rollout restart deployment trip-service -n production
   kubectl rollout restart deployment social-service -n production
   kubectl rollout restart deployment moderation-service -n production
   ```

#### Test OAuth2 Authentication

```bash
# Get access token from Keycloak
curl -X POST http://<EXTERNAL-IP>/auth/realms/traversium/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=user-service" \
  -d "client_secret=<your-client-secret>" \
  -d "grant_type=client_credentials"

# Use the access token to call moderation service
TOKEN="<access-token-from-above>"
curl -X POST http://<EXTERNAL-IP>/moderation/analyze \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Test content"}'
```

### 3. Deploy Prometheus

```bash
# Add Prometheus repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Install Prometheus
helm install prometheus prometheus-community/prometheus --namespace monitoring


# Verify Prometheus is running
kubectl get pods -n monitoring | grep prometheus
```

### 3. Deploy Grafana

```bash
# Add Grafana repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Grafana
helm install grafana grafana/grafana \
    --namespace monitoring \
    -f monitoring/grafana-values.yaml

# Get Grafana admin password
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

kubectl apply -f monitoring/grafana-ingress.yaml

# Verify Grafana is running
kubectl get pods -n monitoring | grep grafana
```

**Access Grafana:**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
# Open http://localhost:3000
# Username: admin
# Password: (from command above)
```

### 4. Deploy ELK Stack (Elasticsearch, Kibana, Fluent Bit)

#### 4.1 Install Elasticsearch

```bash
# Add Elastic repository
helm repo add elastic https://helm.elastic.co
helm repo update

# Create EFK namespace
kubectl create namespace efk-prod

# Install Elasticsearch (lightweight production)
helm install elasticsearch elastic/elasticsearch \
  --namespace efk-prod \
  --set replicas=1 \
  --set minimumMasterNodes=1 \
  --set esJavaOpts="-Xms1g -Xmx1g" \
  --set resources.requests.cpu="500m" \
  --set resources.limits.cpu="1000m" \
  --set resources.requests.memory="2Gi" \
  --set resources.limits.memory="2Gi" \
  --set clusterHealthCheckParams="wait_for_status=yellow&timeout=60s" \
  --set volumeClaimTemplate.resources.requests.storage=20Gi

# Wait for Elasticsearch to be ready (may take 2-3 minutes)
kubectl get pods -n efk-prod -w

# Get Elasticsearch password
kubectl get secret elasticsearch-master-credentials -n efk-prod -o jsonpath="{.data.password}" | base64 --decode ; echo
```

#### 4.2 Configure Log Retention Policy

```bash
# Wait for Elasticsearch to be ready
kubectl wait --for=condition=ready pod -l app=elasticsearch-master -n efk-prod --timeout=300s

# Get Elasticsearch password
ELASTIC_PASSWORD=$(kubectl get secret elasticsearch-master-credentials -n efk-prod -o jsonpath="{.data.password}" | base64 --decode)

# Create lifecycle policy to delete logs after 3 days
kubectl exec elasticsearch-master-0 -n efk-prod -- curl -s -k -u elastic:$ELASTIC_PASSWORD \
  -X PUT 'https://localhost:9200/_ilm/policy/fluentbit-cleanup-policy' \
  -H 'Content-Type: application/json' -d '{
    "policy": {
      "phases": {
        "delete": {
          "min_age": "3d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'
```

#### 4.3 Install Kibana

```bash
# Install Kibana
helm install kibana elastic/kibana \
    --namespace efk-prod \
    -f efk/kibana-values.yaml

# Verify Kibana is running
kubectl get pods -n efk-prod | grep kibana
```

**Access Kibana:**

**Option 1: Port Forwarding (Quick Access)**
```bash
# Port-forward to access locally
kubectl port-forward -n efk-prod svc/kibana-kibana 5601:5601

# Open http://localhost:5601
# Username: elastic
# Password: (from Elasticsearch password command)
```

**Option 2: Ingress (Production Access)**

Deploy the Kibana Ingress to expose Kibana through the nginx ingress controller:

```bash
# Apply the Kibana ingress to production namespace
kubectl apply -f efk/kibana-ingress.yaml -n efk-prod
```

After deploying the ingress, Kibana will be accessible at:
```
http://<EXTERNAL-IP>/
```

To get the Ingress IP:
```bash
kubectl get svc -n production nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Note:** The ingress configuration in `efk/kibana-ingress.yaml` routes traffic on path `/` to the Kibana service on port 5601.

#### 4.4 Install Fluent Bit

```bash
# Add Fluent Helm repository
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

# Install Fluent Bit
helm install fluent-bit fluent/fluent-bit \
  --namespace efk-prod \
  -f efk/fluent-bit-values.yaml \
  --set resources.requests.cpu="200m" \
  --set resources.limits.cpu="500m" \
  --set resources.requests.memory="256Mi" \
  --set resources.limits.memory="512Mi"

# Verify Fluent Bit is running on all nodes
kubectl get pods -n efk-prod | grep fluent-bit
```

### 5. Deploy Ingress Controller
Then install the ingress controller with the static ip and the resource group where the ip is located:

```bash
# Add ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install nginx ingress controller in production namespace
 helm install nginx-ingress ingress-nginx/ingress-nginx \
     --namespace production \
     --set controller.service.loadBalancerIP="20.240.93.121" \
     --set controller.service.externalTrafficPolicy=Local \
     --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-resource-group"="rg-aks-traversium-test-sweden" \
     --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \

  
helm install traversium-ingress ./ingress -n production -f ./ingress/values-prod.yaml

# Wait for external IP to be assigned
kubectl get svc -n production nginx-ingress-ingress-nginx-controller -w
```

**Note the EXTERNAL-IP** - this is your public IP for accessing services.

Because we have dns set up to s static ip address, we need to add rules to bind the ingress controller to that ip.

first check the error message when installing the ingress controller without the static ip:
```bash
kubectl describe service nginx-ingress-ingress-nginx-controller -n production
```

Then you get the identity of resource by running:
```bash
az aks show \
  --resource-group rg-aks-traversium-test-sweden \
  --name aks-traversium-test \
  --query identity.principalId \
  --output tsv
```

Then assign the role to the identity:
```bash
az role assignment create \
    --assignee <principal-id-from-above> \
    --role "Network Contributor" \
    --scope /subscriptions/<your-subscription-id>/resourceGroups/rg-aks-traversium-test-sweden
```

Delete and wait 30 second s and then reinstall the ingress controller with the static ip as shown above.

### 6. Setup HTTPS with Let's Encrypt

Configure automatic SSL/TLS certificates using cert-manager and Let's Encrypt.

#### 6.1 Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.1/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s

# Verify installation
kubectl get pods -n cert-manager
```

#### 6.2 Create Let's Encrypt ClusterIssuer

Create the cert-manager configuration directory and ClusterIssuer:

```bash
# Create directory
mkdir -p cert-manager

# Apply the ClusterIssuer
kubectl apply -f cert-manager/letsencrypt-production.yaml

# Verify ClusterIssuer is ready
kubectl get clusterissuer
```
#### 6.3 Update Ingress for TLS

The ingress is already configured for TLS in `values-prod.yaml`. Deploy/upgrade the ingress:

```bash
# Deploy or upgrade ingress with TLS enabled
helm upgrade traversium-ingress ./ingress -n production -f ./ingress/values-prod.yaml

# Verify ingress has TLS configuration
kubectl get ingress traversium-ingress -n production -o yaml | grep -A 5 "tls:"
```

#### 6.4 Verify Certificate Issuance

```bash
# Check certificate status (should show READY: True)
kubectl get certificate -n production

# Check certificate details
kubectl describe certificate traversium-tls -n production

# Verify certificate is valid
kubectl get secret traversium-tls -n production -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -issuer -dates
```

The certificate should show:
- **Subject:** CN=api.traversium.com
- **Issuer:** Let's Encrypt (R13 or similar)
- **Valid:** 90 days from issuance

#### 6.5 Test HTTPS Access

```bash
# Test HTTPS endpoint (replace with your domain)
curl -I https://api.traversium.com/

# Should return HTTP/2 200 with valid SSL certificate
```
---

## Deploy Application Services

Deploy all microservices to the production namespace.

### 1. Deploy User Service

```bash
helm upgrade --install user-service ./user-service \
  -f ./user-service/values.yaml \
  -f ./user-service/values-prod.yaml \
  -n production

# Verify deployment
kubectl get pods -n production -l app=user-service
```

### 2. Deploy Trip Service

```bash
helm upgrade --install trip-service ./trip-service \
  -f ./trip-service/values.yaml \
  -f ./trip-service/values-prod.yaml \
  -n production

# Verify deployment
kubectl get pods -n production -l app=trip-service
```

### 3. Deploy Audit Service

```bash
helm upgrade --install audit-service ./audit-service \
  -f ./audit-service/values.yaml \
  -f ./audit-service/values-prod.yaml \
  -n production

# Verify deployment
kubectl get pods -n production -l app=audit-service
```

### 4. Deploy Social Service

```bash
helm upgrade --install social-service ./social-service \
  -f ./social-service/values.yaml \
  -f ./social-service/values-prod.yaml \
  -n production

# Verify deployment
kubectl get pods -n production -l app=social-service
```

### 5. Deploy Notification Service

```bash
helm upgrade --install notification-service ./notification-service \
  -f ./notification-service/values.yaml \
  -f ./notification-service/values-prod.yaml \
  -n production

# Verify deployment
kubectl get pods -n production -l app=notification-service
```

### 6. Deploy File Storage Service

```bash
helm upgrade --install file-storage-service ./file-storage-service \
  -f ./file-storage-service/values.yaml \
  -f ./file-storage-service/values-prod.yaml \
  -n production

# Verify deployment
kubectl get pods -n production -l app=file-storage-service
```

### 7. Deploy Moderation Service

```bash
helm upgrade --install moderation-service ./moderation-service \
  -f ./moderation-service/values.yaml \
  -f ./moderation-service/values-prod.yaml \
  -n production

# Verify deployment
kubectl get pods -n production -l app=moderation-service
```

### 8. Deploy Config Server

The Config Server provides centralized configuration management for all microservices.

**Note:** If your repository is public, you can skip this step.

#### 8.1 Deploy Config Server

```bash
# Update Helm dependencies
helm dependency update config-server/

# Deploy config-server
helm upgrade --install config-server ./config-server \
  -f ./config-server/values.yaml \
  -f ./config-server/values-prod.yaml \
  -n production

# Verify deployment
kubectl get pods -n production -l app=config-server
kubectl logs -n production -l app=config-server --tail=50
```

Wait for the pod to be in `Running` state and `READY 1/1`.

#### 8.2 Test Config Server

```bash
# Port forward to access config-server
kubectl port-forward -n production svc/config-server 8888:80

# In another terminal, test fetching configuration
curl http://localhost:8888/UserService/default
curl http://localhost:8888/TripService/default
curl http://localhost:8888/NotificationService/default
curl http://localhost:8888/ModerationService/default
```

You should see the configuration properties from your TraversiumConfiguration repository.

### 9. Deploy Ingress Rules

```bash
helm upgrade --install ingress ./ingress \
  -f ./ingress/values.yaml \
  -f ./ingress/values-prod.yaml \
  -n production

# Verify ingress
kubectl get ingress -n production
```

### 10. Setup GitHub Webhook for Config Server

The webhook enables automatic configuration refresh when you push changes to the TraversiumConfiguration repository.

#### 10.1 Get Ingress External IP

```bash
# Get the external IP
kubectl get svc -n production nginx-ingress-ingress-nginx-controller
```

Note the `EXTERNAL-IP` (e.g., `4.165.58.183`)

#### 10.2 Verify Config Server Webhook Endpoint

The ingress automatically exposes the config-server's `/monitor` endpoint:

```bash
# Test the webhook endpoint (should return 200 or 405)
curl -X POST http://<EXTERNAL-IP>/monitor

# Example:
curl -X POST http://4.165.58.183/monitor
```

It is fine to get 400 - Bad Request since no payload is sent.

#### 10.3 Configure GitHub Webhook

1. Go to your **TraversiumConfiguration** repository on GitHub
2. Navigate to **Settings** → **Webhooks** → **Add webhook**
3. Configure the webhook:
   - **Payload URL**: `http://<EXTERNAL-IP>/monitor` (e.g., `http://4.165.58.183/monitor`)
   - **Content type**: `application/json`
   - **Secret**: (optional, leave blank or set a secret)
   - **Which events would you like to trigger this webhook?**: Select **Just the push event**
   - **Active**: ✓ Check this box

4. Click **Add webhook**

#### 10.4 Test the Webhook

1. Make a change to one of the configuration files in TraversiumConfiguration repository:
   ```bash
   # Example: Edit UserService.properties
   # Add or change a property:
   test.property=hello-from-config-server
   ```

2. Commit and push to the `main` branch:
   ```bash
   git add .
   git commit -m "Test config refresh"
   git push origin main
   ```

3. Verify webhook delivery in GitHub:
   - Go to **Settings** → **Webhooks**
   - Click on your webhook
   - Check **Recent Deliveries** tab
   - Should see a successful delivery (green checkmark)

4. Monitor config-server logs to see the refresh event:
   ```bash
   kubectl logs -f -n production -l app=config-server
   ```

   You should see logs indicating:
   - Webhook received
   - Configuration refreshed
   - Refresh event published to Kafka (springCloudBus topic)

5. Monitor microservices to see if they received the refresh event:
   ```bash
   # Check if services received the refresh event
   kubectl logs -n production -l app=user-service | grep -i "refresh"
   ```

#### 10.5 How It Works

When you push configuration changes to the main branch:

1. **GitHub** sends a webhook POST request to `http://<EXTERNAL-IP>/monitor`
2. **Ingress** routes the request to **config-server**
3. **Config-server** receives the webhook and pulls latest configuration from Git
4. **Config-server** publishes a refresh event to Kafka (`springCloudBus` topic)
5. **All microservices** subscribed to Kafka receive the refresh event
6. **Microservices** reload their configuration from config-server **without restarting**

---

## Verify Deployment

### Check All Production Pods

```bash
kubectl get pods -n production
```

All pods should be in `Running` state with `READY 1/1` (or `3/3` for services with multiple replicas).

### Check All Services

```bash
kubectl get svc -n production
```

### Check Ingress

```bash
kubectl get ingress -n production
kubectl describe ingress traversium-ingress -n production
```

### Check Infrastructure

```bash
# Kafka
kubectl get pods -n kafka-prod
kubectl get svc -n kafka-prod

# Monitoring (Prometheus & Grafana)
kubectl get pods -n monitoring

# Logging (ELK Stack)
kubectl get pods -n efk-prod
```

---

## Access Services

### Get External IP and Domain

```bash
# Get external IP
kubectl get svc -n production nginx-ingress-ingress-nginx-controller

# Verify DNS is configured (should return your static IP)
nslookup api.traversium.com
```

Note the `EXTERNAL-IP` (e.g., `20.240.93.121`)

### Service Endpoints

**With Domain (HTTPS - Recommended):**

If you have configured DNS and HTTPS (see [Setup HTTPS with Let's Encrypt](#6-setup-https-with-lets-encrypt)):

- **User Service Swagger:** `https://api.traversium.com/users/swagger-ui.html`
- **Trip Service Swagger:** `https://api.traversium.com/trips/swagger-ui.html`
- **Audit Service Swagger:** `https://api.traversium.com/audit/swagger-ui.html`
- **Social Service Swagger:** `https://api.traversium.com/social/swagger-ui.html`
- **Notification Service Swagger:** `https://api.traversium.com/notifications/swagger-ui.html`
- **File Storage Service Swagger:** `https://api.traversium.com/files/swagger-ui.html`
- **Config Server Webhook:** `https://api.traversium.com/monitor` (for GitHub webhooks)

**Without Domain (HTTP - Direct IP):**

If you haven't configured DNS yet, access via IP:

- **User Service Swagger:** `http://<EXTERNAL-IP>/users/swagger-ui.html`
- **Trip Service Swagger:** `http://<EXTERNAL-IP>/trips/swagger-ui.html`
- **Audit Service Swagger:** `http://<EXTERNAL-IP>/audit/swagger-ui.html`
- **Social Service Swagger:** `http://<EXTERNAL-IP>/social/swagger-ui.html`
- **Notification Service Swagger:** `http://<EXTERNAL-IP>/notifications/swagger-ui.html`
- **File Storage Service Swagger:** `http://<EXTERNAL-IP>/files/swagger-ui.html`
- **Config Server Webhook:** `http://<EXTERNAL-IP>/monitor` (for GitHub webhooks)

**Note:** Replace `<EXTERNAL-IP>` with your actual external IP (e.g., `20.240.93.121`)

### API Endpoints

**With HTTPS (Recommended):**
- **User API:** `https://api.traversium.com/users/rest/v1/users`
- **Trip API:** `https://api.traversium.com/trips/rest/v1/trips`
- **Social API:** `https://api.traversium.com/social/rest/v1/posts`
- **Notification API:** `https://api.traversium.com/notifications/rest/v1/notifications`

**With HTTP (Direct IP):**
- **User API:** `http://<EXTERNAL-IP>/users/rest/v1/users`
- **Trip API:** `http://<EXTERNAL-IP>/trips/rest/v1/trips`
- **Social API:** `http://<EXTERNAL-IP>/social/rest/v1/posts`
- **Notification API:** `http://<EXTERNAL-IP>/notifications/rest/v1/notifications`

### Monitoring & Logging

#### Prometheus
```bash
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# Access: http://localhost:9090
```

#### Grafana
```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
# Access: http://localhost:3000
# Username: admin
# Password: (see deployment step)
```

#### Kibana (ELK)

**Option 1: Port Forwarding**
```bash
kubectl port-forward -n efk-prod svc/kibana-kibana 5601:5601
# Access: http://localhost:5601
# Username: elastic
# Password: (see Elasticsearch deployment step)
```

**Option 2: Ingress (Production)**
```bash
# Deploy Kibana ingress
kubectl apply -f efk/kibana-ingress.yaml -n efk-prod

# Access: http://<EXTERNAL-IP>/
# Username: elastic
# Password: (see Elasticsearch deployment step)
```

---

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n production

# Describe pod for events
kubectl describe pod <pod-name> -n production

# Check logs
kubectl logs <pod-name> -n production

# Check previous logs if crashed
kubectl logs <pod-name> -n production --previous
```

### Service Not Accessible

```bash
# Check service exists
kubectl get svc -n production

# Check ingress configuration
kubectl describe ingress traversium-ingress -n production

# Check nginx ingress controller logs
kubectl logs -n production -l app.kubernetes.io/name=ingress-nginx
```

### Database Connection Issues

```bash
# Verify database secret exists
kubectl get secret <secret-name> -n production

# Check secret contents
kubectl get secret <secret-name> -n production -o jsonpath='{.data.url}' | base64 -d

# Common fixes:
# 1. Verify database name matches (e.g., "auditor" not "audit")
# 2. Check Neon database is not suspended
# 3. Verify credentials are correct
```

### Kafka Connection Issues

```bash
# Check Kafka is running
kubectl get pods -n kafka-prod
kubectl get svc -n kafka-prod

# Check Kafka logs
kubectl logs -n kafka-prod kafka-controller-0

# Verify bootstrap server configuration
helm get values <service-name> -n production | grep bootstrapServers
# Should be: kafka.kafka-prod.svc.cluster.local:9092
```

### View All Logs

```bash
# All pods in production
kubectl logs -n production --all-containers=true --tail=100

# Specific service
kubectl logs -n production -l app=user-service --tail=50

# Follow logs in real-time
kubectl logs -n production -l app=user-service -f
```

---

## Updating Services

### Update Image Version

```bash
# Edit values-prod.yaml
# Change image.tag to new version

# Upgrade deployment
helm upgrade user-service ./user-service \
  -f ./user-service/values.yaml \
  -f ./user-service/values-prod.yaml \
  -n production

# Check rollout status
kubectl rollout status deployment user-service -n production
```

### Rollback Deployment

```bash
# View revision history
helm history user-service -n production

# Rollback to previous version
helm rollback user-service -n production

# Rollback to specific revision
helm rollback user-service 2 -n production
```

---

## Cleanup

### Delete All Services

```bash
# Delete all application services
helm uninstall user-service -n production
helm uninstall trip-service -n production
helm uninstall audit-service -n production
helm uninstall social-service -n production
helm uninstall notification-service -n production
helm uninstall file-storage-service -n production
helm uninstall moderation-service -n production
helm uninstall config-server -n production
helm uninstall ingress -n production
helm uninstall nginx-ingress -n production

# Delete infrastructure
helm uninstall elasticsearch -n efk-prod
helm uninstall prometheus -n monitoring
helm uninstall grafana -n monitoring
helm uninstall elasticsearch -n efk-prod
helm uninstall kibana -n efk-prod
helm uninstall fluent-bit -n efk-prod

# Delete namespaces
kubectl delete namespace production
kubectl delete namespace kafka-prod
kubectl delete namespace monitoring
kubectl delete namespace efk-prod
```
