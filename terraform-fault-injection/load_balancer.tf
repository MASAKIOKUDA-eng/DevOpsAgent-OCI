################################################################################
# OCI Load Balancer
#
# 注入された障害:
# [FAULT-LB-01] 単一サブネットのみ指定 - 可用性の欠如（デプロイ可能）
# [FAULT-LB-02] ヘルスチェックのパスが存在しないエンドポイント(/api/healthcheck)
# [FAULT-LB-03] バックエンドセットのポートとコンテナポートの不一致(8080 vs 80)
# [FAULT-LB-04] アクセスログが無効化されている
################################################################################

# Load Balancer本体
# [FAULT-LB-01] 単一サブネットのみ → 可用性の問題（デプロイ自体は成功する）
resource "oci_load_balancer_load_balancer" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-lb"
  shape          = "flexible"

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }

  # [FAULT-LB-01] 単一サブネットのみ - 可用性に問題
  subnet_ids = [oci_core_subnet.public_ad1.id]

  is_private                 = false
  network_security_group_ids = [oci_core_network_security_group.lb.id]

  # [FAULT-LB-04] アクセスログ無効 - 監査・トラブルシュート不能
  # 本来は OCI Logging サービスと連携すべき

  freeform_tags = {
    Name = "${var.project_name}-lb"
  }
}

# バックエンドセット
resource "oci_load_balancer_backend_set" "app" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  name             = "${var.project_name}-backend-set"
  policy           = "ROUND_ROBIN"

  # [FAULT-LB-02] ヘルスチェックが存在しないパスを参照
  # [FAULT-LB-03] ポート8080を指定しているが、nginxコンテナはポート80で起動
  health_checker {
    protocol            = "HTTP"
    port                = 8080              # nginx はポート80 - ポート不一致
    url_path            = "/api/healthcheck" # nginx は / で200返す - パス不一致
    interval_ms         = 5000
    timeout_in_millis   = 3000
    retries             = 3
    return_code         = 200
  }
}

# バックエンド（コンテナインスタンスのVNIC IPを動的に参照）
# [FAULT-LB-03] ポート8080でバックエンド登録 - nginx はポート80でリッスン
resource "oci_load_balancer_backend" "app" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  backendset_name  = oci_load_balancer_backend_set.app.name
  ip_address       = oci_container_instances_container_instance.app.vnics[0].private_ip
  port             = 8080  # nginx はポート80でリッスン - ポート不一致
  weight           = 1
}

# HTTPリスナー
resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.main.id
  name                     = "${var.project_name}-http-listener"
  default_backend_set_name = oci_load_balancer_backend_set.app.name
  port                     = 80
  protocol                 = "HTTP"

  # HTTPS へのリダイレクトなし - 本来はHTTPSを使用すべき
  # SSL証明書の設定もなし
}
