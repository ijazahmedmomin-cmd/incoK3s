{{- define "nginx-env.fullname" -}}
{{ .Release.Name }}
{{- end }}

{{- define "nginx-env.labels" -}}
app.kubernetes.io/name: {{ include "nginx-env.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
