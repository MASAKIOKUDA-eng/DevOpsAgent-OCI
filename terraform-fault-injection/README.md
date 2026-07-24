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

> **参考**: [AWS DevOps Agent 公式ドキュメント](https://docs.aws.amazon.com/devopsagent/latest/userguide/what-is.html)

AWS DevOps Agent は、インシデント対応を自動化するフロンティアエージェントです。
OCI リソースを監視するには、Agent Space にカスタム MCP サーバーを登録し、
OCI テレメトリを DevOps Agent の調査対象に含める必要があります。

### 全体アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS 環境 (us-east-1 / ap-northeast-1)                          │
│                                                                  │
│  ┌──────────────────────────────────────┐                        │
│  │  AWS DevOps Agent Space              │                        │
│  │  ┌────────────┐  ┌────────────────┐  │                        │
│  │  │ Topology   │  │ Investigation  │  │                        │
│  │  │ (自動検出)  │  │ (RCA実行)      │  │                        │
│  │  └────────────┘  └────────────────┘  │                        │
│  │         │                  │          │                        │
│  │  ┌──────┴──────────────────┴───────┐  │                        │
│  │  │ カスタム MCP サーバー (OCI用)    │  │                        │
│  │  │ - OCI Compute/Network ツール    │  │                        │
│  │  │ - OCI Database ツール           │  │                        │
│  │  │ - OCI Monitoring ツール         │  │                        │
│  │  └────────────────────────────────┘  │                        │
│  └──────────────────────────────────────┘                        │
│                     │                                             │
│                     │ HTTPS (OCI REST API)                        │
└─────────────────────┼─────────────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  OCI 環境 (ap-tokyo-1)                                           │
│  [VCN] → [Load Balancer] → [Container Instances] → [DB System]  │
└─────────────────────────────────────────────────────────────────┘
```

### Step 1: Agent Space の作成（Terraform）

> 参考: [Getting started with AWS DevOps Agent using Terraform](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-getting-started-with-aws-devops-agent-using-terraform.html)

`awscc` プロバイダーの `awscc_devopsagent_agent_space` リソースで Agent Space を作成します。

```hcl
# providers.tf
terraform {
  required_providers {
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.0"
    }
  }
}

provider "awscc" {
  region = "ap-northeast-1"  # 東京リージョン (サポート対象)
}
```

```hcl
# agent_space.tf
resource "awscc_devopsagent_agent_space" "main" {
  agent_space_name = "oci-fault-detection"

  # Operator App（Web UI）の設定
  operator_app_config {
    iam_identity_center_config {
      instance_arn = var.idc_instance_arn
    }
  }

  tags = [{
    key   = "Project"
    value = "DevOpsAgent-OCI"
  }]
}
```

```hcl
# iam.tf - DevOps Agent が AWS リソースにアクセスするためのIAMロール
resource "aws_iam_role" "devops_agent" {
  name = "DevOpsAgentRole-AgentSpace"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "aidevops.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "devops_agent" {
  role       = aws_iam_role.devops_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}
```

```hcl
# association.tf - AWS アカウントを Agent Space に関連付け
resource "awscc_devopsagent_association" "aws_account" {
  agent_space_id = awscc_devopsagent_agent_space.main.agent_space_id
  service_id     = "aws"
  type           = "Aws"

  aws_configuration {
    account_id  = data.aws_caller_identity.current.account_id
    iam_role_id = aws_iam_role.devops_agent.arn
  }
}
```

### Step 2: OCI 用カスタム MCP サーバーの構築と登録

> 参考: [Connecting MCP Servers](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-integrations-and-knowledge-connecting-mcp-servers.html)

MCP サーバーを登録すると、DevOps Agent がインシデント調査時に OCI リソースの状態を
取得・分析できるようになります。MCP サーバーはアカウントレベルで登録され、
Agent Space 単位で使用するツールを選択できます。

#### 2-1. OCI 認証情報を AWS Secrets Manager に保存

```bash
# OCI API キー（秘密鍵）を保存
aws secretsmanager create-secret \
  --name "devops-agent/oci-api-key" \
  --secret-string file://~/.oci/oci_api_key.pem

# OCI 接続設定を保存
aws secretsmanager create-secret \
  --name "devops-agent/oci-config" \
  --secret-string '{
    "tenancy_ocid": "ocid1.tenancy.oc1..xxxxx",
    "user_ocid": "ocid1.user.oc1..xxxxx",
    "fingerprint": "xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx",
    "region": "ap-tokyo-1",
    "compartment_id": "ocid1.compartment.oc1..xxxxx"
  }'
```

#### 2-2. OCI MCP サーバーの実装例（Lambda）

```python
# lambda/oci_mcp_server/handler.py
"""
OCI リソース情報を取得する MCP サーバー (AWS Lambda)
DevOps Agent から呼び出され、OCI の VCN/NSG/LB/DB 等の状態を返す
"""
import json
import oci
import boto3

def get_oci_config():
    """AWS Secrets Manager から OCI 認証情報を取得"""
    sm = boto3.client("secretsmanager")
    config_str = sm.get_secret_value(SecretId="devops-agent/oci-config")["SecretString"]
    key_pem = sm.get_secret_value(SecretId="devops-agent/oci-api-key")["SecretString"]
    config = json.loads(config_str)
    config["key_content"] = key_pem
    return config

def list_vcn_security_issues(event, context):
    """VCN/NSG のセキュリティ問題を検出する MCP ツール"""
    config = get_oci_config()
    vn_client = oci.core.VirtualNetworkClient(config)

    # NSG ルールを取得して問題を検出
    nsgs = vn_client.list_network_security_groups(
        compartment_id=config["compartment_id"]
    ).data

    issues = []
    for nsg in nsgs:
        rules = vn_client.list_network_security_group_security_rules(
            network_security_group_id=nsg.id
        ).data
        for rule in rules:
            if rule.source == "0.0.0.0/0" and rule.direction == "INGRESS":
                issues.append({
                    "nsg": nsg.display_name,
                    "issue": "全世界からのIngressを許可",
                    "protocol": rule.protocol,
                    "severity": "HIGH"
                })
    return {"issues": issues}

def get_db_system_status(event, context):
    """PostgreSQL DB System の状態を取得する MCP ツール"""
    config = get_oci_config()
    psql_client = oci.psql.PostgresqlClient(config)

    db_systems = psql_client.list_db_systems(
        compartment_id=config["compartment_id"]
    ).data.items

    results = []
    for db in db_systems:
        detail = psql_client.get_db_system(db_system_id=db.id).data
        results.append({
            "name": detail.display_name,
            "state": detail.lifecycle_state,
            "instance_count": detail.instance_count,
            "is_ha": detail.instance_count > 1,
            "backup_policy": detail.management_policy.backup_policy.kind
        })
    return {"db_systems": results}
```

#### 2-3. MCP サーバーの登録（AWS CLI）

```bash
# DevOps Agent に MCP サーバーを登録
aws devops-agent register-mcp-server \
  --agent-space-id <agent-space-id> \
  --name "oci-infrastructure" \
  --description "OCI infrastructure inspection tools for fault detection" \
  --endpoint-url "https://<lambda-function-url>" \
  --tools '[
    {
      "name": "list_vcn_security_issues",
      "description": "List security issues in OCI VCN/NSG configurations"
    },
    {
      "name": "get_db_system_status",
      "description": "Get OCI PostgreSQL DB System status and HA configuration"
    },
    {
      "name": "get_load_balancer_health",
      "description": "Check OCI Load Balancer backend health status"
    },
    {
      "name": "get_container_instance_status",
      "description": "Get OCI Container Instance runtime status"
    }
  ]'
```

### Step 3: OCI 監視からの Webhook 連携

> 参考: [Invoking DevOps Agent through Webhook](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-capabilities-for-aws-devops-agent-invoking-devops-agent-through-webhook.html)

OCI Monitoring のアラームが発火した際に、Webhook で DevOps Agent の調査を自動起動できます。

```bash
# DevOps Agent の Webhook URL を取得
WEBHOOK_URL=$(aws devops-agent get-webhook-url \
  --agent-space-id <agent-space-id> \
  --output text)
```

```hcl
# OCI 側: アラーム → Notification Topic → HTTPS Webhook
resource "oci_monitoring_alarm" "lb_unhealthy" {
  compartment_id = var.compartment_id
  display_name   = "LB-Backend-Unhealthy"
  namespace      = "oci_lbaas"
  query          = "UnHealthyBackendServers[1m].count() > 0"
  severity       = "CRITICAL"
  is_enabled     = true

  destinations = [oci_ons_notification_topic.devops_agent.id]
}

resource "oci_ons_notification_topic" "devops_agent" {
  compartment_id = var.compartment_id
  name           = "devops-agent-webhook"
}

# OCI → AWS DevOps Agent Webhook へ通知
resource "oci_ons_subscription" "devops_agent_webhook" {
  compartment_id = var.compartment_id
  topic_id       = oci_ons_notification_topic.devops_agent.id
  protocol       = "HTTPS"
  endpoint       = "<DEVOPS_AGENT_WEBHOOK_URL>"
}
```

### Step 4: DevOps Agent API でタスクを作成

> 参考: [CreateBacklogTask API](https://docs.aws.amazon.com/boto3/latest/reference/services/devops-agent/client/create_backlog_task.html)

プログラムから直接 DevOps Agent に調査タスクを作成することもできます。

```python
import boto3

client = boto3.client("devops-agent", region_name="ap-northeast-1")

# OCI で問題を検知した場合に調査タスクを作成
response = client.create_backlog_task(
    agentSpaceId="<agent-space-id>",
    taskType="INVESTIGATION",
    title="OCI Load Balancer backend unhealthy - port mismatch suspected",
    description="""
    OCI Load Balancer のバックエンドが unhealthy 状態です。
    ヘルスチェックポート(8080)とコンテナポート(80)の不一致が疑われます。

    影響リソース:
    - Load Balancer: fault-test-lb
    - Backend Set: fault-test-backend-set
    - Container Instance: fault-test-container-instance

    OCI Region: ap-tokyo-1
    Compartment: <compartment-ocid>
    """,
    priority="HIGH"
)

print(f"Investigation task created: {response['taskId']}")
```

### Step 5: GitHub 連携による Terraform デプロイ追跡

> 参考: [Associating AWS resources with project deployments](https://docs.aws.amazon.com/devopsagent/latest/userguide/configuring-capabilities-for-aws-devops-agent-connecting-to-cicd-pipelines-associating-aws-resources-with-project-deployments.html)

DevOps Agent は GitHub/GitLab と連携し、Terraform のデプロイを追跡できます。

```yaml
# .github/workflows/oci-deploy-and-notify.yml
name: Deploy OCI Infrastructure & Notify DevOps Agent

on:
  push:
    branches: [main]
    paths: ['terraform-fault-injection/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4

      - name: Configure OCI credentials
        env:
          OCI_CLI_KEY_CONTENT: ${{ secrets.OCI_PRIVATE_KEY }}
        run: |
          mkdir -p ~/.oci
          echo "$OCI_CLI_KEY_CONTENT" > ~/.oci/oci_api_key.pem
          chmod 600 ~/.oci/oci_api_key.pem

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Apply
        working-directory: terraform-fault-injection
        env:
          TF_VAR_tenancy_ocid: ${{ secrets.OCI_TENANCY_OCID }}
          TF_VAR_compartment_id: ${{ secrets.OCI_COMPARTMENT_OCID }}
        run: |
          terraform init
          terraform apply -auto-approve

      - name: Notify DevOps Agent of deployment
        env:
          AWS_REGION: ap-northeast-1
        run: |
          # DevOps Agent にデプロイ完了を通知
          aws devops-agent create-backlog-task \
            --agent-space-id ${{ secrets.AGENT_SPACE_ID }} \
            --task-type EVALUATION \
            --title "OCI Terraform deployment completed - evaluate infrastructure" \
            --description "Terraform apply completed for OCI fault-injection test environment. Evaluate deployed resources for security and reliability issues." \
            --priority MEDIUM
```

### Step 6: OCI 側の IAM ポリシー設定

MCP サーバー（Lambda）が OCI API を呼び出すために必要な OCI IAM ポリシーです。

```hcl
# OCI IAM Policy - DevOps Agent MCP サーバー用（読み取り専用）
resource "oci_identity_policy" "devops_agent_readonly" {
  compartment_id = var.tenancy_ocid
  name           = "devops-agent-readonly-policy"
  description    = "Allow DevOps Agent MCP server to inspect OCI resources"

  statements = [
    "Allow group DevOpsAgentGroup to inspect vcns in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect subnets in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect network-security-groups in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect route-tables in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect load-balancers in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect compute-container-instances in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect postgresql-db-systems in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to read metrics in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to read log-content in compartment id ${var.compartment_id}",
    "Allow group DevOpsAgentGroup to inspect compartments in tenancy",
  ]
}
```

### ネットワーク接続オプション

OCI リソースへの動的アクセスが必要な場合のネットワーク接続方式です。

| 接続方式 | ユースケース | 設定難易度 |
|---------|-------------|-----------|
| **インターネット経由（HTTPS）** | OCI REST API 呼び出し、LB ヘルスチェック | 低 |
| **OCI FastConnect + AWS Direct Connect** | プライベート接続（本番向け） | 高 |
| **IPSec VPN** | AWS VPC ↔ OCI VCN のサイト間 VPN | 中 |
| **AWS PrivateLink → Lambda → OCI API** | プライベートサブネットからのAPI呼び出し | 中 |

> **注**: DevOps Agent の MCP サーバー（Lambda）から OCI REST API への呼び出しは
> インターネット経由（HTTPS）で行われます。Lambda に VPC を設定する場合は
> NAT Gateway が必要です。

### 接続確認チェックリスト

```bash
# 1. Agent Space の確認
aws devops-agent list-agent-spaces

# 2. MCP サーバーの登録確認
aws devops-agent list-mcp-servers --agent-space-id <agent-space-id>

# 3. OCI 認証テスト（Lambda から実行される処理と同等）
python -c "
import oci, json, boto3
sm = boto3.client('secretsmanager')
config = json.loads(sm.get_secret_value(SecretId='devops-agent/oci-config')['SecretString'])
config['key_content'] = sm.get_secret_value(SecretId='devops-agent/oci-api-key')['SecretString']
client = oci.core.VirtualNetworkClient(config)
vcns = client.list_vcns(compartment_id=config['compartment_id']).data
print(f'Found {len(vcns)} VCNs')
"

# 4. Webhook テスト
curl -X POST <WEBHOOK_URL> \
  -H "Content-Type: application/json" \
  -d '{"title": "Test: OCI LB unhealthy backend", "priority": "LOW"}'

# 5. DevOps Agent Web App でトポロジ確認
# https://console.aws.amazon.com/aidevops → Agent Space → Topology
```

---

## 注意事項

- ⚠️ このコードは**デプロイ可能**ですが意図的に問題を含んでいます
- ⚠️ テスト終了後は必ず `terraform destroy` で削除してください
- ⚠️ デプロイ中は利用料金が発生します（概算: $5-6/日）
- ⚠️ DBがパブリック公開されるため、テスト以外の目的で使用しないでください
