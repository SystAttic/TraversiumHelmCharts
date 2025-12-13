{{- define "common.labels" -}}
app: {{ .name }}
version: {{ .Values.image.tag | default "latest" }}
{{- end -}}

{{- define "common.imagePullSecrets" -}}
{{- if .Values.secrets.imagePullSecret }}
imagePullSecrets:
  - name: {{ .Values.secrets.imagePullSecret }}
{{- end }}
{{- end -}}

{{- define "common.firebaseVolumeMount" -}}
- name: firebase-config
  mountPath: /opt/{{ .serviceName }}/conf
  readOnly: true
{{- end -}}

{{- define "common.firebaseVolume" -}}
- name: firebase-config
  secret:
    secretName: {{ .Values.secrets.firebaseSecret }}
{{- end -}}

{{- define "common.databaseEnv" -}}
- name: SPRING_DATASOURCE_URL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.databaseSecret }}
      key: url
- name: SPRING_DATASOURCE_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.databaseSecret }}
      key: username
- name: SPRING_DATASOURCE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.secrets.databaseSecret }}
      key: password
{{ end -}}

{{- define "common.hikariEnv" -}}
- name: SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE
  value: "0"
- name: SPRING_DATASOURCE_HIKARI_INITIALIZATION_FAIL_TIMEOUT
  value: "0"
- name: SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE
  value: "5"
- name: SPRING_DATASOURCE_HIKARI_IDLE_TIMEOUT
  value: "15000"
- name: SPRING_DATASOURCE_HIKARI_CONNECTION_TIMEOUT
  value: "30000"
- name: SPRING_DATASOURCE_HIKARI_MAX_LIFETIME
  value: "300000"
- name: SPRING_DATASOURCE_HIKARI_KEEPALIVE_TIME
  value: "0"
{{ end -}}

{{- define "common.flywayJpaEnv" -}}
- name: SPRING_FLYWAY_ENABLED
  value: "true"
- name: SPRING_FLYWAY_LOCATIONS
  value: "classpath:db/migration/tenant"
- name: SPRING_DATASOURCE_INITIALIZATION_MODE
  value: "never"
- name: SPRING_SQL_INIT_MODE
  value: "never"
- name: SPRING_JPA_HIBERNATE_DDL_AUTO
  value: "none"
- name: SPRING_JPA_OPEN_IN_VIEW
  value: "false"
{{ end -}}

{{- define "common.kafkaBootstrap" -}}
- name: SPRING_KAFKA_BOOTSTRAP_SERVERS
  value: "{{ .Values.kafka.bootstrapServers }}"
{{ end -}}

{{- define "common.serverEnv" -}}
- name: SERVER_PORT
  value: "{{ .Values.service.port }}"
- name: SERVER_SERVLET_CONTEXT_PATH
  value: "{{ .contextPath }}"
{{ end -}}

{{- define "common.managementEnv" -}}
- name: MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE
  value: "health,info,prometheus"
- name: MANAGEMENT_ENDPOINT_HEALTH_SHOW_DETAILS
  value: "always"
- name: MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED
  value: "true"
- name: MANAGEMENT_HEALTH_LIVENESSSTATE_ENABLED
  value: "true"
- name: MANAGEMENT_HEALTH_READINESSSTATE_ENABLED
  value: "true"
{{ end -}}

{{- define "common.managementHealthWithDb" -}}
- name: MANAGEMENT_ENDPOINT_HEALTH_GROUP_READINESS_INCLUDE
  value: "readinessState,db,diskSpace"
- name: MANAGEMENT_ENDPOINT_HEALTH_GROUP_READINESS_SHOW_DETAILS
  value: "always"
- name: MANAGEMENT_ENDPOINT_HEALTH_GROUP_LIVENESS_INCLUDE
  value: "livenessState,ping"
- name: MANAGEMENT_ENDPOINT_HEALTH_GROUP_LIVENESS_SHOW_DETAILS
  value: "always"
{{ end -}}

{{- define "common.managementHealthNoDb" -}}
- name: MANAGEMENT_ENDPOINT_HEALTH_GROUP_READINESS_INCLUDE
  value: "readinessState,diskSpace"
- name: MANAGEMENT_ENDPOINT_HEALTH_GROUP_READINESS_SHOW_DETAILS
  value: "always"
- name: MANAGEMENT_ENDPOINT_HEALTH_GROUP_LIVENESS_INCLUDE
  value: "livenessState,ping"
- name: MANAGEMENT_ENDPOINT_HEALTH_GROUP_LIVENESS_SHOW_DETAILS
  value: "always"
{{ end -}}

{{- define "common.standardEnv" -}}
{{ include "common.databaseEnv" . -}}
{{ include "common.serverEnv" . -}}
{{ include "common.flywayJpaEnv" . -}}
{{ include "common.hikariEnv" . -}}
{{ include "common.kafkaBootstrap" . -}}
{{ include "common.managementEnv" . -}}
{{ include "common.managementHealthWithDb" . -}}
{{- end -}}

{{- define "common.prometheusAnnotations" -}}
prometheus.io/scrape: "true"
prometheus.io/path: "{{ .contextPath }}/actuator/prometheus"
prometheus.io/port: "{{ .Values.service.port }}"
{{- end -}}
