################################################################################
# OCI Container Instances
#
# 注入された障害:
# [FAULT-CI-01] コンテナのShape/OCPUが極端に不足
# [FAULT-CI-02] コンテナインスタンスが1つのみで冗長性なし
# [FAULT-CI-03] コンテナポート(3000)とバックエンドセットポート(8080)の不一致
# [FAULT-CI-04] ログ設定が欠落 - OCI Loggingへの出力なし
# [FAULT-CI-05] IAMポリシーにOCIRからのPull権限がない
################################################################################

# コンテナインスタンス
# [FAULT-CI-01] OCPU: 1, Memory: 1GB は本番アプリには不十分
# [FAULT-CI-02] 単一インスタンスのみ - 冗長性なし
resource "oci_container_instances_container_instance" "app" {
  compartment_id               = var.compartment_id
  availability_domain          = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name                 = "${var.project_name}-container-instance"
  container_restart_policy     = "ALWAYS"

  # [FAULT-CI-01] 極端に少ないリソース
  shape = "CI.Standard.E4.Flex"
  shape_config {
    ocpus         = 1     # 最小構成 - 本番には不十分
    memory_in_gbs = 1     # 極端に少ない - Node.jsアプリには最低2GB推奨
  }

  containers {
    display_name = "app"
    image_url    = "nrt.ocir.io/tenancy-namespace/myapp:latest"

    # [FAULT-CI-03] コンテナはポート3000だが、LBバックエンドはポート8080にヘルスチェック
    resource_config {
      memory_limit_in_gbs = 1
      vcpus_limit         = 1
    }

    # [FAULT-CI-04] ログ設定なし - 障害時のデバッグ不能
    # 本来はOCI Loggingサービスと連携すべき
    # oci_logging_log リソースの設定が必要

    environment_variables = {
      PORT         = "3000"
      # DBの接続情報をハードコード - OCI Vault を使うべき
      DATABASE_URL = "postgresql://admin:password123@${var.project_name}-db.subnet.vcn.oraclevcn.com:5432/myapp"
    }
  }

  vnics {
    subnet_id             = oci_core_subnet.private_ad1.id
    display_name          = "${var.project_name}-container-vnic"
    nsg_ids               = [oci_core_network_security_group.container.id]
    is_public_ip_assigned = false  # NATもないためインターネットアクセス不可
  }

  # [FAULT-CI-05] OCIR Pull用のイメージPullシークレットが設定されていない
  # 本来は以下が必要:
  # image_pull_secrets {
  #   registry_endpoint = "nrt.ocir.io"
  #   secret_type       = "VAULT"
  #   secret_id         = oci_vault_secret.ocir_auth.id
  # }

  # Auto Scalingなし - トラフィック増加に対応不能
  # OCI Container InstancesはAutoScaling非対応のため、
  # 本来はOKE (Kubernetes) の使用を検討すべき

  freeform_tags = {
    Name = "${var.project_name}-container-instance"
  }
}

# [FAULT-CI-05] OCIRからのPull権限ポリシーが存在しない
# 本来は以下のようなIAMポリシーが必要:
# resource "oci_identity_policy" "container_ocir_pull" {
#   compartment_id = var.tenancy_ocid
#   name           = "${var.project_name}-container-ocir-policy"
#   description    = "Allow container instances to pull images from OCIR"
#   statements = [
#     "Allow dynamic-group ${var.project_name}-container-dg to read repos in compartment id ${var.compartment_id}",
#     "Allow dynamic-group ${var.project_name}-container-dg to use keys in compartment id ${var.compartment_id}"
#   ]
# }

# ダイナミックグループも未定義
# resource "oci_identity_dynamic_group" "container_dg" {
#   compartment_id = var.tenancy_ocid
#   name           = "${var.project_name}-container-dg"
#   description    = "Dynamic group for container instances"
#   matching_rule  = "ALL {resource.type = 'computecontainerinstance', resource.compartment.id = '${var.compartment_id}'}"
# }

# Availability Domains データソース
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}
