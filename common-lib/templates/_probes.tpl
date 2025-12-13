{{- define "common.startupProbe" -}}
startupProbe:
  httpGet:
    path: {{ .contextPath }}/actuator/health/liveness
    port: {{ .Values.service.port }}
  initialDelaySeconds: {{ .Values.probes.startup.initialDelaySeconds | default 30 }}
  periodSeconds: {{ .Values.probes.startup.periodSeconds | default 10 }}
  timeoutSeconds: {{ .Values.probes.startup.timeoutSeconds | default 5 }}
  failureThreshold: {{ .Values.probes.startup.failureThreshold | default 30 }}
{{ end -}}

{{- define "common.livenessProbe" -}}
livenessProbe:
  httpGet:
    path: {{ .contextPath }}/actuator/health/liveness
    port: {{ .Values.service.port }}
  initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds | default 5 }}
  periodSeconds: {{ .Values.probes.liveness.periodSeconds | default 10 }}
  timeoutSeconds: {{ .Values.probes.liveness.timeoutSeconds | default 5 }}
  failureThreshold: {{ .Values.probes.liveness.failureThreshold | default 3 }}
{{ end -}}

{{ define "common.readinessProbe" -}}
readinessProbe:
  httpGet:
    path: {{ .contextPath }}/actuator/health/readiness
    port: {{ .Values.service.port }}
  initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds | default 5 }}
  periodSeconds: {{ .Values.probes.readiness.periodSeconds | default 10 }}
  timeoutSeconds: {{ .Values.probes.readiness.timeoutSeconds | default 5 }}
  failureThreshold: {{ .Values.probes.readiness.failureThreshold | default 3 }}
{{ end -}}

{{ define "common.probes" -}}
{{ include "common.startupProbe" . }}
{{ include "common.livenessProbe" . }}
{{ include "common.readinessProbe" . }}
{{- end -}}
