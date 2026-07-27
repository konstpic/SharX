{{- define "secret.isEnabled" -}}
{{- if hasKey . "enabled" -}}
{{- if .enabled -}}true{{- end -}}
{{- else -}}true{{- end -}}
{{- end -}}
