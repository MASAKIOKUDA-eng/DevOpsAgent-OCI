# OCI DevOps Agent 障害検知テスト用 Terraform コード

## 概要

このTerraformコードは、OCI DevOps Agentの障害検知能力を検証するために、
シンプルなWebサービス構成（Load Balancer + Container Instances + PostgreSQL DB System）に**意図的な障害**を注入したものです。

## アーキテクチャ

```
Internet
    |
[OCI Load Balancer]
    |
[OCI Container Instances]
    |
[OCI PostgreSQL DB System]
```

## AWSとOCIのリソース対応表

| AWS | OCI | ファイル |
|-----|-----|---------|
| VPC | VCN (Virtual Cloud Network) | vcn.tf |
| Security Group | Network Security Group (NSG) | network_security_groups.tf |
| ALB (Application Load Balancer) | OCI Load Balancer | load_balancer.tf |
| ECS Fargate | OCI Container Instances | container_instances.tf |
| RDS PostgreSQL | OCI Database System (PostgreSQL) | database.tf |
| NAT Gateway | OCI NAT Gateway | vcn.tf |
| Internet Gateway | OCI Internet Gateway | vcn.tf |
| IAM Role/Policy | OCI IAM Dynamic Group/Policy | container_instances.tf |
| CloudWatch Logs | OCI Logging | container_instances.tf |
| Secrets Manager | OCI Vault | database.tf |
| KMS | OCI Vault KMS | database.tf |

## 注入された障害カテゴリ

| カテゴリ | 障害数 | 説明 |
|---------|--------|------|
| ネットワーク | 3 | NSG設定ミス、ルーティング不備 |
| 可用性 | 3 | 単一AD、レプリカなし |
| パフォーマンス | 2 | リソース不足、スケーリング不備 |
| セキュリティ | 4 | パブリック公開、暗号化なし |
| 設定 | 3 | ヘルスチェック不備、ポート不一致 |

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
├── load_balancer.tf                # OCI Load Balancer
├── container_instances.tf          # OCI Container Instances
└── database.tf                     # OCI PostgreSQL DB System
```

## 使い方

このコードは**実際にデプロイするものではありません**。
DevOps Agentに静的解析させ、障害を検知できるかを確認するためのテストケースです。

```bash
# DevOps Agentに解析させる例
devops-agent analyze ./terraform-fault-injection/
```

## 前提条件

- Terraform >= 1.5.0
- OCI Provider ~> 5.0
- OCI CLI設定済み（~/.oci/config）

## 注意事項

- ⚠️ このコードは意図的に問題を含んでいます
- ⚠️ 本番環境には絶対にデプロイしないでください
- ⚠️ 学習・テスト目的でのみ使用してください
