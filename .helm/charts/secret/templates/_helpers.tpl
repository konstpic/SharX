{{- define "secret.fullname" -}}
{{- $name := .name -}}
{{- printf "%s-%s" $.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "secret.labels" -}}
app.kubernetes.io/name: secret
app.kubernetes.io/instance: {{ $.Release.Name }}
app.kubernetes.io/managed-by: {{ $.Release.Service }}
{{- end -}}
