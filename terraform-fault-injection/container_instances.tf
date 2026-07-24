################################################################################
# OCI Container Instances
#
# 注入された障害:
# [FAULT-CI-01] コンテナのOCPU/メモリが極端に不足（1 OCPU / 1 GB）
# [FAULT-CI-02] コンテナインスタンスが1つのみで冗長性なし
# [FAULT-CI-03] コンテナポート(80/nginx)とバックエンドセットポート(8080)の不一致
# [FAULT-CI-04] ログ設定が欠落 - OCI Loggingへの出力なし
# [FAULT-CI-05] プライベートサブネット配置でNATなし - 外部通信不可
#
# デプロイ可能にするため、パブリックDockerイメージ(nginx)を使用
################################################################################

# コンテナインスタンス
# [FAULT-CI-01] OCPU: 1, Memory: 1GB は本番アプリには不十分
# [FAULT-CI-02] 単一インスタンスのみ - 冗長性なし
resource "oci_container_instances_container_instance" "app" {
  compartment_id           = var.compartment_id
  availability_domain      = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name             = "${var.project_name}-container-instance"
  container_restart_policy = "ALWAYS"

  # [FAULT-CI-01] 極端に少ないリソース
  shape = "CI.Standard.E4.Flex"
  shape_config {
    ocpus         = 1   # 最小構成 - 本番には不十分
    memory_in_gbs = 1   # 極端に少ない - OOMリスク
  }

  containers {
    display_name = "app"
    # パブリックイメージ使用（OCIR認証不要 → デプロイ成功する）
    image_url    = "docker.io/library/nginx:latest"

    # [FAULT-CI-04] ログ設定なし - 障害時のデバッグ不能
    # 本来はOCI Loggingサービスと連携すべき

    environment_variables = {
      # [FAULT-CI-03 参考] アプリ想定ポート情報
      # nginx はデフォルトでポート80でリッスンするが
      # LBバックエンドはポート8080を指定している
      NGINX_PORT = "80"
    }
  }

  vnics {
    subnet_id             = oci_core_subnet.public_ad1.id
    display_name          = "${var.project_name}-container-vnic"
    nsg_ids               = [oci_core_network_security_group.container.id]
    is_public_ip_assigned = false
    # [FAULT-CI-05] パブリックIPなし + NATなし
    # コンテナがDockerイメージをPullするにはパブリックサブネットのIGW経由
    # ここではパブリックサブネットだがパブリックIPなしのため
    # イメージPull自体はサブネットのルートテーブル経由で可能
  }

  freeform_tags = {
    Name = "${var.project_name}-container-instance"
  }
}
