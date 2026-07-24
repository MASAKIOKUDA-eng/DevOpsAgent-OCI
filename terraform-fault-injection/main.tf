################################################################################
# OCI DevOps Agent 障害検知テスト - メイン設定
# 注意: このコードは意図的に障害を含んでいます
#
# デプロイは正常に完了しますが、運用上の問題がAgentによって検知されるべきです
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  region = var.oci_region

  # 認証情報は環境変数または~/.oci/configから取得
  # tenancy_ocid     = var.tenancy_ocid
  # user_ocid        = var.user_ocid
  # fingerprint      = var.fingerprint
  # private_key_path = var.private_key_path
}
