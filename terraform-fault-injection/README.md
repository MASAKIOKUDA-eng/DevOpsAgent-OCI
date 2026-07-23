# OCI DevOps Agent 障害検知テスト用 Terraform コード

## 概要

このTerraformコードは、OCI DevOps Agentの障害検知能力を検証するために、
シンプルなWebサービス構成（Load Balancer + Container Instances + PostgreSQL DB System）に
**意図的な障害**を注入したものです。

**特徴**: すべてのコードは `terraform apply` で正常にデプロイできますが、
運用上・セキュリティ上の問題が意図的に残されています。

## アーキテクチャ

```
Internet
    |
[OCI Load Balancer] (port 80)
    |
    | ← ポート8080でバックエンド登録 (FAULT)
    |
[OCI Container Instance - nginx] (port 80)
    |
    | ← 接続情報あるがNSGで制限不十分 (FAULT)
    |
[OCI PostgreSQL DB System] (port 5432)
```

## AWSとOCIのリソース対応表

| AWS | OCI | ファイル |
|-----|-----|---------|
| VPC | VCN (Virtual Cloud Network) | vcn.tf |
| Security Group | Network Security Group (NSG) | network_security_groups.tf |
| ALB (Application Load Balancer) | OCI Flexible Load Balancer | load_balancer.tf |
| ECS Fargate | OCI Container Instances | container_instances.tf |
| RDS PostgreSQL | OCI Database with PostgreSQL | database.tf |
| NAT Gateway | OCI NAT Gateway（未作成=障害） | vcn.tf |
| Internet Gateway | OCI Internet Gateway | vcn.tf |
| CloudWatch Logs | OCI Logging（未設定=障害） | - |
| Secrets Manager | OCI Vault（未使用=障害） | database.tf |
| KMS | OCI Vault KMS（未使用=障害） | database.tf |

## 注入された障害（21件）

| カテゴリ | 障害数 | 代表的な障害 |
|---------|--------|-------------|
| セキュリティ | 4件 | NSG全開放、DB公開、パスワードハードコード |
| 可用性 | 4件 | 単一AD、HA無効、冗長性なし |
| 設定 | 4件 | ポート不一致、ヘルスチェック不正 |
| ネットワーク | 2件 | NATなし、サブネット不足 |
| パフォーマンス | 1件 | リソース不足 |
| 運用 | 4件 | ログ無効、バックアップなし、削除保護なし |

詳細は [FAULT_CATALOG.md](./FAULT_CATALOG.md) を参照してください。

## ファイル構成

```
terraform-fault-injection/
├── README.md                       # このファイル
├── FAULT_CATALOG.md                # 障害一覧と期待される検知結果
├── main.tf                         # プロバイダー設定
├── variables.tf                    # 変数定義
├── outputs.tf                      # 出力定義
├── vcn.tf                          # VCN・ネットワーク構成
├── network_security_groups.tf      # ネットワークセキュリティグループ
├── load_balancer.tf                # OCI Flexible Load Balancer
├── container_instances.tf          # OCI Container Instances (nginx)
└── database.tf                     # OCI Database with PostgreSQL
```

## 使い方

### 前提条件

- Terraform >= 1.5.0
- OCI Provider ~> 6.0
- OCI CLI設定済み（~/.oci/config）
- 対象コンパートメントへの適切なIAMポリシー

### デプロイ

```bash
# 変数ファイル作成
cat > terraform.tfvars <<EOF
tenancy_ocid   = "ocid1.tenancy.oc1..your-tenancy-ocid"
compartment_id = "ocid1.compartment.oc1..your-compartment-ocid"
oci_region     = "ap-tokyo-1"
EOF

# 初期化・デプロイ
terraform init
terraform plan
terraform apply -auto-approve
```

### DevOps Agent による解析

```bash
# 静的解析
devops-agent analyze ./terraform-fault-injection/

# デプロイ後の動的検証
devops-agent verify --deployed ./terraform-fault-injection/
```

### クリーンアップ

```bash
terraform destroy -auto-approve
```

## 注意事項

- ⚠️ このコードは**デプロイ可能**ですが意図的に問題を含んでいます
- ⚠️ テスト終了後は必ず `terraform destroy` で削除してください
- ⚠️ デプロイ中は利用料金が発生します（概算: $5-6/日）
- ⚠️ DBがパブリック公開されるため、テスト以外の目的で使用しないでください
