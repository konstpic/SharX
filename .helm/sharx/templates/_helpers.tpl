{{- define "sharx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sharx.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "sharx.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "sharx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "sharx.labels" -}}
helm.sh/chart: {{ include "sharx.chart" . }}
app.kubernetes.io/name: {{ include "sharx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: sharx
{{- end -}}

{{- define "sharx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sharx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "sharx.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "sharx.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "sharx.panelImage" -}}
{{- $registry := .Values.global.imageRegistry -}}
{{- $repo := .Values.panel.image.repository -}}
{{- $tag := .Values.panel.image.tag | default .Chart.AppVersion | default "latest" -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}

{{- define "sharx.postgresImage" -}}
{{- $registry := .Values.global.imageRegistry -}}
{{- $repo := .Values.postgres.image.repository -}}
{{- $tag := .Values.postgres.image.tag | default "16-alpine" -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}

{{- define "sharx.postgresFullname" -}}
{{- printf "%s-postgres" (include "sharx.fullname" .) -}}
{{- end -}}
