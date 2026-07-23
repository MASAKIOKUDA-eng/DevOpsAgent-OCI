################################################################################
# OCI Database System (PostgreSQL)
#
# 注入された障害:
# [FAULT-DB-01] 高可用性(HA)無効 - 単一障害点（instance_count = 1）
# [FAULT-DB-02] パブリックサブネットに配置 - インターネットからDB直接アクセス可能
# [FAULT-DB-03] 暗号化にカスタマー管理キー未使用 - デフォルト暗号化のみ
# [FAULT-DB-04] 自動バックアップ無効 - データ復旧不能
# [FAULT-DB-05] パスワードがvariableのdefaultにハードコード - OCI Vaultを使うべき
# [FAULT-DB-06] 削除保護なし（lifecycle prevent_destroy未設定）
################################################################################

# OCI PostgreSQL Database System
resource "oci_psql_db_system" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-db"
  db_version     = "14"

  # [FAULT-DB-01] HA無効 - 単一ノードのみ
  shape {
    id = "PostgreSQL.VM.Standard.E4.Flex.2.32GB"
  }
  instance_count = 1

  # ストレージ設定
  storage_details {
    is_regionally_durable = false  # [FAULT-DB-01] リージョナル耐久性なし
    system_type           = "OCI_OPTIMIZED_STORAGE"
    availability_domain   = data.oci_identity_availability_domains.ads.availability_domains[0].name
  }

  # ネットワーク設定
  # [FAULT-DB-02] パブリックサブネットに配置 - 本来はプライベートサブネットに配置すべき
  network_details {
    subnet_id = oci_core_subnet.public_ad1.id
    nsg_ids   = [oci_core_network_security_group.db.id]
  }

  # 認証情報
  # [FAULT-DB-05] パスワードが variables.tf のデフォルト値にハードコードされている
  credentials {
    username = "admin"
    password_details {
      password_type = "PLAIN_TEXT"
      password      = var.db_admin_password
    }
  }

  # [FAULT-DB-04] 自動バックアップ無効
  management_policy {
    backup_policy {
      kind = "NONE"  # バックアップなし - データ復旧不能
    }
  }

  # [FAULT-DB-06] 削除保護なし
  # 本来は以下が必要:
  # lifecycle {
  #   prevent_destroy = true
  # }

  # [FAULT-DB-03] カスタマー管理キー未使用
  # 本来は以下が必要:
  # kms_key_id = oci_kms_key.db_key.id

  freeform_tags = {
    Name = "${var.project_name}-db"
  }
}
