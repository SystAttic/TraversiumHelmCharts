# Helm Charts with Common Library Dependencies - Usage Guide

## Overview

This Helm charts repository uses a **common library chart** to share reusable templates across all microservices, reducing code duplication by 67%.

## What is the Common Library?

The `common-lib/` chart is a Helm **library chart** (not deployable itself) that provides reusable templates for:

- Health probes (liveness & readiness)
- Database configuration (credentials, Hikari pool, Flyway, JPA)
- Kafka bootstrap configuration
- Firebase volume mounts
- Image pull secrets
- Server settings (port, context path, health endpoints)

## Quick Start

### Step 1: Update Dependencies

**Before deploying any service**, you must download the common library dependency:

```bash
# Update all services at once 
./update-all-dependencies.sh
```

This creates:
- `charts/` directory → Contains the downloaded `common-lib` chart
- `Chart.lock` → Locks the exact version of dependencies

**IMPORTANT**:
- Always run `./update-all-dependencies.sh` after pulling from Git

### Step 2: Deploy Services

```bash
# Install new service
helm install trip-service ./trip-service

# Upgrade existing service
helm upgrade --install trip-service ./trip-service
```

## Directory Structure

```
TraversiumHelmCharts/
├── common-lib/                      # Shared library chart
│   ├── Chart.yaml                   # Library chart metadata
│   └── templates/
│       ├── _deployment.tpl          # Deployment templates
│       └── _probes.tpl              # Health probe templates
│
├── trip-service/                    # Example service
│   ├── Chart.yaml                   # References common-lib dependency
│   ├── values.yaml                  # Service configuration
│   ├── charts/                      # Generated - 
│   │   └── common-lib-1.0.0.tgz    # Downloaded dependency
│   ├── Chart.lock                   # Generated - locks dependency versions
│   └── templates/
│       ├── deployment.yaml          # Uses common templates
│       └── service.yaml
│
├── [other services...]
├── .gitignore                       # Excludes charts/ and Chart.lock
└── update-all-dependencies.sh       # Helper script
```

## How Dependencies Work

### 1. Chart.yaml declares the dependency

```yaml
# trip-service/Chart.yaml
apiVersion: v2              # v2 required for dependencies
name: trip-service
version: 1.0.0

dependencies:
  - name: common-lib
    version: 1.0.0
    repository: "file://../common-lib"   # Local file path
```

## Available Common Templates

### Basic Templates

| Template | Usage | Description |
|----------|-------|-------------|
| `common.imagePullSecrets` | `{{- include "common.imagePullSecrets" . \| nindent 6 }}` | Image pull secrets |
| `common.firebaseVolume` | `{{- include "common.firebaseVolume" . \| nindent 8 }}` | Firebase secret volume |
| `common.firebaseVolumeMount` | `{{- include "common.firebaseVolumeMount" (dict "serviceName" "trip-service" "Values" .Values) \| nindent 12 }}` | Firebase volume mount |

### Environment Variables

| Template | Provides | Env Vars Count |
|----------|----------|----------------|
| `common.databaseEnv` | Database credentials | 3 |
| `common.serverEnv` | Server settings | 3 |
| `common.hikariEnv` | Hikari pool config | 7 |
| `common.flywayJpaEnv` | Flyway & JPA config | 7 |
| `common.kafkaBootstrap` | Kafka servers | 1 |
| `common.standardEnv` | All above combined | 21 |

### Health Probes

| Template | Usage |
|----------|-------|
| `common.probes` | `{{- include "common.probes" (dict "contextPath" "/trips" "Values" .Values) \| nindent 10 }}` |

## Example: Service Using Common Library

### deployment.yaml (simplified)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trip-service
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: trip-service
  template:
    metadata:
      labels:
        app: trip-service
    spec:
      {{- include "common.imagePullSecrets" . | nindent 6 }}
      containers:
        - name: trip-service
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: {{ .Values.service.port }}
          volumeMounts:
            {{- include "common.firebaseVolumeMount" (dict "serviceName" "trip-service" "Values" .Values) | nindent 12 }}
          env:
            {{- include "common.standardEnv" (dict "contextPath" "/trips" "Values" .Values) | nindent 12 }}
            - name: SPRING_KAFKA_AUDIT_TOPIC
              value: "{{ .Values.kafka.auditTopic }}"
            - name: SPRING_KAFKA_NOTIFICATION_TOPIC
              value: "{{ .Values.kafka.notificationTopic }}"
          {{- include "common.probes" (dict "contextPath" "/trips" "Values" .Values) | nindent 10 }}
      volumes:
        {{- include "common.firebaseVolume" . | nindent 8 }}
```

## Modifying the Common Library

### Making Changes to common-lib

1. **Edit the templates** in `common-lib/templates/`:
   ```bash
   # Example: Change default probe timing
   vim common-lib/templates/_probes.tpl
   ```

2. **Update all service dependencies** to get the changes:
   ```bash
   ./update-all-dependencies.sh
   ```

3. **Test the changes**:
   ```bash
   helm template trip-service ./trip-service
   helm lint ./trip-service
   ```

4. **Deploy updated services**:
   ```bash
   helm upgrade trip-service ./trip-service
   ```

### Example: Adding a New Common Template

**Add to `common-lib/templates/_deployment.tpl`:**
```yaml
{{/*
Redis connection settings
Usage: {{ include "common.redisEnv" . | nindent 12 }}
*/}}
{{- define "common.redisEnv" -}}
- name: SPRING_REDIS_HOST
  value: "{{ .Values.redis.host }}"
- name: SPRING_REDIS_PORT
  value: "{{ .Values.redis.port }}"
{{ end -}}
```

**Use in service deployment:**
```yaml
env:
  {{- include "common.standardEnv" (dict "contextPath" "/trips" "Values" .Values) | nindent 12 }}
  {{- include "common.redisEnv" . | nindent 12 }}
```

## Testing & Validation

### Validate Templates

```bash
# Render templates to see generated YAML
helm template trip-service ./trip-service

# Lint for errors
helm lint ./trip-service

# Check specific section
helm template trip-service ./trip-service | grep -A 20 "env:"
```
