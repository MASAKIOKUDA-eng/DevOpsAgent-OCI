################################################################################
# OCI Load Balancer
#
# 注入された障害:
# [FAULT-LB-01] 単一サブネットのみ指定 - 可用性の欠如
# [FAULT-LB-02] ヘルスチェックのパスが存在しないエンドポイント
# [FAULT-LB-03] バックエンドセットのポートとコンテナポートの不一致
# [FAULT-LB-04] アクセスログが無効化されている
################################################################################

# Load Balancer本体
# [FAULT-LB-01] subnet_idsに単一サブネットのみ → 可用性の問題
resource "oci_load_balancer_load_balancer" "main" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-lb"
  shape          = "flexible"

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }

  # 単一サブネットのみ - 本来は複数サブネット（異なるAD）に配置すべき
  subnet_ids = [oci_core_subnet.public_ad1.id]

  is_private                 = false
  network_security_group_ids = [oci_core_network_security_group.lb.id]

  # [FAULT-LB-04] アクセスログ無効 - 監査・トラブルシュート不能
  # 本来は以下のようにログを有効化すべき:
  # oci_logging_log リソースでアクセスログを設定

  freeform_tags = {
    Name = "${var.project_name}-lb"
  }
}

# バックエンドセット
# [FAULT-LB-03] ポート8080を指定しているが、コンテナはポート3000で起動
resource "oci_load_balancer_backend_set" "app" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  name             = "${var.project_name}-backend-set"
  policy           = "ROUND_ROBIN"

  # [FAULT-LB-02] 存在しないヘルスチェックパス
  health_checker {
    protocol            = "HTTP"
    port                = 8080          # コンテナはポート3000でリッスン
    url_path            = "/api/healthcheck"  # アプリは /health で応答する
    interval_ms         = 5000
    timeout_in_millis   = 3000
    retries             = 2
    return_code         = 200
  }
}

# バックエンド
# [FAULT-LB-03] ポート8080でバックエンド登録 - コンテナはポート3000
resource "oci_load_balancer_backend" "app" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  backendset_name  = oci_load_balancer_backend_set.app.name
  ip_address       = "10.0.10.10"  # コンテナインスタンスのIPを想定
  port             = 8080          # コンテナはポート3000でリッスン - ポート不一致
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
