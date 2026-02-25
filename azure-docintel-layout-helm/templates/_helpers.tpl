{{- define "azure-docintel-layout.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "azure-docintel-layout.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "azure-docintel-layout.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "azure-docintel-layout.labels" -}}
app.kubernetes.io/name: {{ include "azure-docintel-layout.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "azure-docintel-layout.selectorLabels" -}}
app.kubernetes.io/name: {{ include "azure-docintel-layout.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "azure-docintel-layout.secretName" -}}
{{- if .Values.secret.nameOverride -}}
{{- .Values.secret.nameOverride -}}
{{- else -}}
{{- printf "%s-secret" (include "azure-docintel-layout.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "azure-docintel-layout.configName" -}}
{{- if .Values.config.nameOverride -}}
{{- .Values.config.nameOverride -}}
{{- else -}}
{{- printf "%s-config" (include "azure-docintel-layout.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "azure-docintel-layout.pvcName" -}}
{{- printf "%s-%s" (include "azure-docintel-layout.fullname" .root) .volume.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

