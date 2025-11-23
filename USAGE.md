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
helm install nginx-ingress ingress-nginx/ingress-nginx

# Deploy your ingress rules
helm install traversium-ingress ./ingress
```

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
