variable "environment_name" {
  description = "Name of the environment"
  type        = string
  default     = "retail-store"
}

variable "istio_enabled" {
  description = "Boolean value that enables istio."
  type        = bool
  default     = false
}

variable "opentelemetry_enabled" {
  description = "Boolean value that enables OpenTelemetry."
  type        = bool
  default     = false
}

variable "enable_grafana" {
  description = "Boolean value that enables Amazon Managed Grafana. Requires AWS SSO to be configured in the account."
  type        = bool
  default     = false
}
