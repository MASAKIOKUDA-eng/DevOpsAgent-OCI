################################################################################
# 変数定義
################################################################################

variable "oci_region" {
  description = "OCI region"
  type        = string
  default     = "ap-tokyo-1"
}

variable "tenancy_ocid" {
  description = "OCI Tenancy OCID"
  type        = string
}

variable "compartment_id" {
  description = "OCI Compartment OCID"
  type        = string
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "fault-test"
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
  # [FAULT-DB-05] デフォルト値にハードコードパスワード - OCI Vaultを使うべき
  default = "FaultTest_Pass123!"
}
