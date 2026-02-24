{{- define "form-recognizer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "form-recognizer.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "form-recognizer.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "form-recognizer.labels" -}}
app.kubernetes.io/name: {{ include "form-recognizer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "form-recognizer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "form-recognizer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "form-recognizer.secretName" -}}
{{- if .Values.secret.nameOverride -}}
{{- .Values.secret.nameOverride -}}
{{- else -}}
{{- printf "%s-secret" (include "form-recognizer.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "form-recognizer.configName" -}}
{{- if .Values.config.nameOverride -}}
{{- .Values.config.nameOverride -}}
{{- else -}}
{{- printf "%s-config" (include "form-recognizer.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "form-recognizer.pvcName" -}}
{{- printf "%s-%s" (include "form-recognizer.fullname" .root) .volume.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

