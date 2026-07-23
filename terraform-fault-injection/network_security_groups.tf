################################################################################
# ネットワークセキュリティグループ (NSG)
#
# 注入された障害:
# [FAULT-SEC-01] LBのNSGが全ポート開放 (0.0.0.0/0 全許可)
# [FAULT-SEC-02] コンテナのNSGがLBからのトラフィックを許可していない（ポート不一致）
# [FAULT-SEC-03] DBのNSGが0.0.0.0/0からのアクセスを許可（パブリック公開）
# [FAULT-SEC-04] コンテナからDBへの通信がNSGで許可されていない
################################################################################

# Load Balancer用ネットワークセキュリティグループ
# [FAULT-SEC-01] 全ポートを0.0.0.0/0に開放 - 本来はHTTP/HTTPSのみにすべき
resource "oci_core_network_security_group" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-lb-nsg"

  freeform_tags = {
    Name = "${var.project_name}-lb-nsg"
  }
}

# [FAULT-SEC-01] 全トラフィック許可 - 本来はport 80, 443のみ
resource "oci_core_network_security_group_security_rule" "lb_ingress_all" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Allow all inbound - FAULT: should be HTTP/HTTPS only"
}

resource "oci_core_network_security_group_security_rule" "lb_egress_all" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound"
}

# コンテナインスタンス用ネットワークセキュリティグループ
# [FAULT-SEC-02] LBからのポート8080を許可しているが、コンテナはポート3000で起動
resource "oci_core_network_security_group" "container" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-container-nsg"

  freeform_tags = {
    Name = "${var.project_name}-container-nsg"
  }
}

# ポート不一致: LBはポート3000にフォワードするが、NSGはポート8080のみ許可
resource "oci_core_network_security_group_security_rule" "container_ingress_lb" {
  network_security_group_id = oci_core_network_security_group.container.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.lb.id
  source_type               = "NETWORK_SECURITY_GROUP"
  description               = "Allow from LB - FAULT: port mismatch"

  tcp_options {
    destination_port_range {
      min = 8080
      max = 8080
    }
  }
}

resource "oci_core_network_security_group_security_rule" "container_egress_all" {
  network_security_group_id = oci_core_network_security_group.container.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound"
}

# DB System用ネットワークセキュリティグループ
# [FAULT-SEC-03] 0.0.0.0/0からのアクセスを許可 - DBがパブリックに公開
# [FAULT-SEC-04] コンテナのNSGからのアクセスではなくCIDRで制限
resource "oci_core_network_security_group" "db" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-db-nsg"

  freeform_tags = {
    Name = "${var.project_name}-db-nsg"
  }
}

# [FAULT-SEC-03] 全世界からDBポートへのアクセスを許可
resource "oci_core_network_security_group_security_rule" "db_ingress_all" {
  network_security_group_id = oci_core_network_security_group.db.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "Allow PostgreSQL from anywhere - FAULT: public exposure"

  tcp_options {
    destination_port_range {
      min = 5432
      max = 5432
    }
  }
}

resource "oci_core_network_security_group_security_rule" "db_egress_all" {
  network_security_group_id = oci_core_network_security_group.db.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound"
}
