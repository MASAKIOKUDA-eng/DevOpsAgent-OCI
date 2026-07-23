################################################################################
# OCI Database System (PostgreSQL)
#
# 注入された障害:
# [FAULT-DB-01] 高可用性(HA)無効 - 単一障害点
# [FAULT-DB-02] パブリックサブネットに配置 - インターネットからDB直接アクセス可能
# [FAULT-DB-03] 暗号化にカスタマー管理キー未使用 - デフォルト暗号化のみ
# [FAULT-DB-04] 自動バックアップ無効 - データ復旧不能
# [FAULT-DB-05] パスワードがハードコード - セキュリティリスク
# [FAULT-DB-06] 削除保護なし
################################################################################

# OCI Database System (PostgreSQL)
resource "oci_psql_db_system" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-db"
  db_version     = "14"

  # システム構成 - 本番には不十分なスペック
  shape = "PostgreSQL.VM.Standard.E4.Flex.2.32GB"
  instance_count = 1  # [FAULT-DB-01] HA無効 - 単一ノードのみ

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

  # データベース設定
  db_configuration_params {
    apply_config = "RESTART"
    config_id    = data.oci_psql_default_configuration.pg14.id
  }

  # 認証情報
  credentials {
    username = "admin"
    # [FAULT-DB-05] パスワードがTerraformコードにハードコード
    password_details {
      password_type = "PLAIN_TEXT"
      password      = "password123"  # OCI Vaultを使用すべき
    }
  }

  # [FAULT-DB-04] 自動バックアップ無効
  management_policy {
    backup_policy {
      kind              = "NONE"  # バックアップなし - データ復旧不能
      # 本来は以下のように設定すべき:
      # kind              = "DAILY"
      # retention_days    = 7
    }
  }

  # [FAULT-DB-06] 削除保護なし
  # 本来は deletion_protection = true に相当する設定が必要
  # OCI では terraform destroy 実行時に保護する仕組みがない

  # [FAULT-DB-03] カスタマー管理キー未使用
  # 本来は以下が必要:
  # kms_key_id = oci_kms_key.db_key.id

  freeform_tags = {
    Name = "${var.project_name}-db"
  }
}

# デフォルト設定のデータソース
data "oci_psql_default_configuration" "pg14" {
  db_version = "14"
  shape      = "PostgreSQL.VM.Standard.E4.Flex.2.32GB"
}
