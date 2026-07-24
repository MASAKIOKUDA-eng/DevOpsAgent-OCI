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

---

## AWS DevOps Agent と OCI リソースの接続方法

AWS 上で動作する DevOps Agent から OCI リソースを解析・監視するための接続設定です。

### 接続アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│  AWS 環境                                           │
│                                                     │
│  [DevOps Agent (EC2/Lambda/ECS)]                    │
│       │                                             │
│       ├── OCI CLI / SDK（API Key 認証）             │
│       ├── Terraform OCI Provider                    │
│       └── OCI REST API 直接呼び出し                 │
│                                                     │
└───────┼─────────────────────────────────────────────┘
        │  HTTPS (443)
        ▼
┌─────────────────────────────────────────────────────┐
│  OCI 環境                                           │
│                                                     │
│  [VCN / LB / Container Instances / DB System]       │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 方法1: OCI API Key 認証（推奨）

AWS 上の DevOps Agent が OCI API を呼び出すための最も標準的な方法です。

#### 1-1. OCI ユーザーと API キーの作成

```bash
# OCI CLI でAPIキーペアを生成
oci setup keys

# 生成されるファイル:
# ~/.oci/oci_api_key.pem       (秘密鍵)
# ~/.oci/oci_api_key_public.pem (公開鍵)
```

#### 1-2. OCI コンソールで公開鍵を登録

1. OCI コンソール → Identity → Users → 対象ユーザー
2. 「API Keys」→「Add API Key」→ 公開鍵をペースト
3. 表示される Fingerprint をメモ

#### 1-3. AWS 側での OCI 認証情報の配置

**オプションA: AWS Secrets Manager に保存（推奨）**

```bash
# OCI 秘密鍵を AWS Secrets Manager に保存
aws secretsmanager create-secret \
  --name "oci/api-key" \
  --secret-string file://~/.oci/oci_api_key.pem

# OCI 接続情報を保存
aws secretsmanager create-secret \
  --name "oci/config" \
  --secret-string '{
    "tenancy_ocid": "ocid1.tenancy.oc1..xxxxx",
    "user_ocid": "ocid1.user.oc1..xxxxx",
    "fingerprint": "xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx",
    "region": "ap-tokyo-1",
    "compartment_id": "ocid1.compartment.oc1..xxxxx"
  }'
```

**オプションB: ~/.oci/config ファイルを直接配置**

```ini
# ~/.oci/config （AWS EC2上のDevOps Agentインスタンスに配置）
[DEFAULT]
user=ocid1.user.oc1..xxxxx
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..xxxxx
region=ap-tokyo-1
key_file=~/.oci/oci_api_key.pem
```

#### 1-4. Terraform OCI Provider の設定

```hcl
# DevOps Agent が OCI リソースの状態を取得する場合
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.oci_region
}
```

### 方法2: OCI Instance Principal（OCI上にAgentを配置する場合）

OCI 上にも DevOps Agent のコンポーネントを配置する場合は、Instance Principal 認証が使えます。

```hcl
# Instance Principal認証 (OCI上のComputeインスタンスから)
provider "oci" {
  auth   = "InstancePrincipal"
  region = var.oci_region
}
```

```bash
# ダイナミックグループの作成が必要
# OCI CLI で作成する例:
oci iam dynamic-group create \
  --compartment-id <tenancy_ocid> \
  --name "DevOpsAgentDG" \
  --matching-rule "ALL {resource.type = 'instance', resource.compartment.id = '<compartment_ocid>'}" \
  --description "DevOps Agent instances"
```

### 方法3: 環境変数による認証

CI/CD パイプライン（GitHub Actions等）から実行する場合に適しています。

```bash
# 環境変数を設定
export TF_VAR_tenancy_ocid="ocid1.tenancy.oc1..xxxxx"
export TF_VAR_user_ocid="ocid1.user.oc1..xxxxx"
export TF_VAR_fingerprint="xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"
export TF_VAR_private_key_path="~/.oci/oci_api_key.pem"
export TF_VAR_compartment_id="ocid1.compartment.oc1..xxxxx"

# OCI CLI 用
export OCI_CLI_TENANCY="ocid1.tenancy.oc1..xxxxx"
export OCI_CLI_USER="ocid1.user.oc1..xxxxx"
export OCI_CLI_FINGERPRINT="xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"
export OCI_CLI_KEY_FILE="~/.oci/oci_api_key.pem"
export OCI_CLI_REGION="ap-tokyo-1"
```

### 方法4: GitHub Actions での AWS → OCI 連携

```yaml
# .github/workflows/oci-fault-detection.yml
name: OCI Fault Detection

on:
  push:
    paths:
      - 'terraform-fault-injection/**'

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure OCI CLI
        env:
          OCI_CLI_USER: ${{ secrets.OCI_USER_OCID }}
          OCI_CLI_TENANCY: ${{ secrets.OCI_TENANCY_OCID }}
          OCI_CLI_FINGERPRINT: ${{ secrets.OCI_FINGERPRINT }}
          OCI_CLI_KEY_CONTENT: ${{ secrets.OCI_PRIVATE_KEY }}
          OCI_CLI_REGION: ap-tokyo-1
        run: |
          mkdir -p ~/.oci
          echo "$OCI_CLI_KEY_CONTENT" > ~/.oci/oci_api_key.pem
          chmod 600 ~/.oci/oci_api_key.pem
          cat > ~/.oci/config <<EOF
          [DEFAULT]
          user=$OCI_CLI_USER
          fingerprint=$OCI_CLI_FINGERPRINT
          tenancy=$OCI_CLI_TENANCY
          region=$OCI_CLI_REGION
          key_file=~/.oci/oci_api_key.pem
          EOF

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.5.0"

      - name: Terraform Init & Plan
        working-directory: terraform-fault-injection
        env:
          TF_VAR_tenancy_ocid: ${{ secrets.OCI_TENANCY_OCID }}
          TF_VAR_compartment_id: ${{ secrets.OCI_COMPARTMENT_OCID }}
        run: |
          terraform init
          terraform plan -no-color

      - name: Run DevOps Agent Analysis
        run: |
          devops-agent analyze ./terraform-fault-injection/ \
            --provider oci \
            --output-format json \
            > analysis-results.json

      - name: Upload Results
        uses: actions/upload-artifact@v4
        with:
          name: fault-analysis-results
          path: analysis-results.json
```

### 必要な IAM ポリシー（OCI側）

DevOps Agent がOCIリソースを読み取るために必要な最小権限ポリシーです。

```hcl
# OCI IAM Policy - DevOps Agent 用（読み取り専用）
resource "oci_identity_policy" "devops_agent_readonly" {
  compartment_id = var.tenancy_ocid
  name           = "devops-agent-readonly-policy"
  description    = "Allow DevOps Agent to inspect OCI resources"

  statements = [
    # ネットワークリソースの読み取り
    "Allow group DevOpsAgentGroup to inspect vcns in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect subnets in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect network-security-groups in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect route-tables in compartment id ${var.compartment_id}",

    # Load Balancer の読み取り
    "Allow group DevOpsAgentGroup to inspect load-balancers in compartment id ${var.compartment_id}",

    # Container Instances の読み取り
    "Allow group DevOpsAgentGroup to inspect compute-container-instances in compartment id ${var.compartment_id}",

    # Database の読み取り
    "Allow group DevOpsAgentGroup to inspect postgresql-db-systems in compartment id ${var.compartment_id}",

    # タグ・コンパートメントの読み取り
    "Allow group DevOpsAgentGroup to inspect compartments in tenancy",
  ]
}
```

### 接続テスト

DevOps Agent から OCI への接続を確認するコマンド例です。

```bash
# OCI CLI でリージョン一覧を取得（認証テスト）
oci iam region list

# コンパートメント内のVCN一覧を取得
oci network vcn list --compartment-id <compartment_ocid>

# Terraform で plan を実行（認証＋権限テスト）
cd terraform-fault-injection
terraform init
terraform plan -var="tenancy_ocid=<tenancy_ocid>" -var="compartment_id=<compartment_ocid>"
```

### AWS DevOps Agent と OCI のネットワーク接続（オプション）

デプロイ済みの OCI リソースに対して動的検証（ヘルスチェック確認等）を行う場合は、
ネットワークレベルの接続も必要です。

| 接続方式 | ユースケース | 設定難易度 |
|---------|-------------|-----------|
| **インターネット経由** | LBのパブリックIPに対するヘルスチェック | 低 |
| **OCI FastConnect + AWS Direct Connect** | プライベート接続（本番向け） | 高 |
| **IPSec VPN** | AWS VPC ↔ OCI VCN のサイト間VPN | 中 |
| **Megaport/Equinix** | サードパーティ経由のクロスクラウド接続 | 中 |

```bash
# デプロイ後にLBのパブリックIPへ接続テスト（インターネット経由）
LB_IP=$(terraform output -raw lb_ip_addresses | jq -r '.[0].ip_address')
curl -v http://${LB_IP}/

# 期待結果: ポート不一致により502 Bad Gatewayまたはタイムアウト
# → DevOps Agent はこの異常を検知すべき
```

---

## 注意事項

- ⚠️ このコードは**デプロイ可能**ですが意図的に問題を含んでいます
- ⚠️ テスト終了後は必ず `terraform destroy` で削除してください
- ⚠️ デプロイ中は利用料金が発生します（概算: $5-6/日）
- ⚠️ DBがパブリック公開されるため、テスト以外の目的で使用しないでください
