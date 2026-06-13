{{- define "carbonmice-admin.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "carbonmice-admin.fullname" -}}
{{- default .Chart.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "carbonmice-admin.labels" -}}
app.kubernetes.io/name: {{ include "carbonmice-admin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{- define "carbonmice-admin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "carbonmice-admin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "carbonmice-admin.secretName" -}}
{{- if .Values.secret.existingSecret -}}
{{- .Values.secret.existingSecret -}}
{{- else -}}
{{- include "carbonmice-admin.fullname" . }}-secret
{{- end -}}
{{- end -}}

{{/* Non-secret env, shared by all pods, via the ConfigMap. */}}
{{- define "carbonmice-admin.envFrom" -}}
- configMapRef:
    name: {{ include "carbonmice-admin.fullname" . }}-env
{{- end -}}

{{/* Secret-derived env for the RUNTIME app role (web + worker). */}}
{{- define "carbonmice-admin.appSecretEnv" -}}
- name: RAILS_MASTER_KEY
  valueFrom:
    secretKeyRef: { name: {{ include "carbonmice-admin.secretName" . }}, key: rails-master-key }
- name: DB_USER
  valueFrom:
    secretKeyRef: { name: {{ include "carbonmice-admin.secretName" . }}, key: app-db-user }
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef: { name: {{ include "carbonmice-admin.secretName" . }}, key: app-db-password }
{{- end -}}

{{/* Secret-derived env for the MIGRATOR role (migrate Job only). */}}
{{- define "carbonmice-admin.migratorSecretEnv" -}}
- name: RAILS_MASTER_KEY
  valueFrom:
    secretKeyRef: { name: {{ include "carbonmice-admin.secretName" . }}, key: rails-master-key }
- name: DB_USER
  valueFrom:
    secretKeyRef: { name: {{ include "carbonmice-admin.secretName" . }}, key: migrator-db-user }
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef: { name: {{ include "carbonmice-admin.secretName" . }}, key: migrator-db-password }
{{- end -}}
