################################################################################
# VCN & ネットワーク構成
#
# 注入された障害:
# [FAULT-NET-01] NATゲートウェイなし - プライベートサブネットからインターネットアクセス不可
# [FAULT-NET-02] 単一AD/FDのみにパブリックサブネット配置 - 可用性の欠如
#
# ※ IGWルートはLBデプロイに必要なため設定済み（デプロイ可能にするため）
################################################################################

# Availability Domains データソース
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# VCN
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.project_name}-vcn"
  dns_label      = "faulttest"

  freeform_tags = {
    Project     = "devops-agent-fault-test"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}

# インターネットゲートウェイ
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-igw"
  enabled        = true
}

################################################################################
# パブリックサブネット
# [FAULT-NET-02] 単一AD/FDのみ - ロードバランサーは複数のサブネットが推奨だが1つしかない
################################################################################
resource "oci_core_subnet" "public_ad1" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "${var.project_name}-public-ad1"
  dns_label                  = "publicad1"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_vcn.main.default_security_list_id]

  freeform_tags = {
    Name = "${var.project_name}-public-ad1"
  }
}

# [FAULT-NET-02] 2つ目のパブリックサブネットが存在しない
# 本来は複数AD/FDに配置してLBの可用性を確保すべき

################################################################################
# プライベートサブネット
# [FAULT-NET-01] NATゲートウェイが存在しないため、
# プライベートサブネットからインターネットアクセス不可
################################################################################
resource "oci_core_subnet" "private_ad1" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.10.0/24"
  display_name               = "${var.project_name}-private-ad1"
  dns_label                  = "privatead1"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_vcn.main.default_security_list_id]

  freeform_tags = {
    Name = "${var.project_name}-private-ad1"
  }
}

resource "oci_core_subnet" "private_ad2" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.11.0/24"
  display_name               = "${var.project_name}-private-ad2"
  dns_label                  = "privatead2"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_vcn.main.default_security_list_id]

  freeform_tags = {
    Name = "${var.project_name}-private-ad2"
  }
}

################################################################################
# ルートテーブル
################################################################################

# パブリック用ルートテーブル - IGWルート設定済み（デプロイ可能にするため）
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.main.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# プライベート用ルートテーブル
# [FAULT-NET-01] NATゲートウェイへのルートがない - 外部通信不可
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-private-rt"

  # NATゲートウェイへのルートが存在しない
  # プライベートサブネットのリソースはインターネットにアクセスできない
  # 本来は oci_core_nat_gateway + route_rules の設定が必要

  freeform_tags = {
    Name = "${var.project_name}-private-rt"
  }
}
