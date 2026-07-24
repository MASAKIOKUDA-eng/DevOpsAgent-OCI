# 障害カタログ - DevOps Agent 検知テスト (OCI版)

このドキュメントは、Terraformコードに注入されたすべての障害と、
DevOps Agentが検知すべき期待される結果をまとめたものです。

**重要**: すべての障害は `terraform apply` が正常に完了するレベルにチューニングされています。
デプロイは成功しますが、運用上・セキュリティ上の問題が残ります。

---

## 障害サマリ

| ID | カテゴリ | 重大度 | ファイル | 概要 |
|----|---------|--------|---------|------|
| FAULT-NET-01 | ネットワーク | High | vcn.tf | NATゲートウェイなし（プライベートサブネット外部通信不可） |
| FAULT-NET-02 | 可用性 | High | vcn.tf | 単一AD/FDのみにパブリックサブネット |
| FAULT-SEC-01 | セキュリティ | High | network_security_groups.tf | LB NSGが全プロトコル・全ポート開放 |
| FAULT-SEC-02 | 設定 | Critical | network_security_groups.tf | コンテナNSGのIngressポート不一致(8080 vs 80) |
| FAULT-SEC-03 | セキュリティ | Critical | network_security_groups.tf | DB NSGが0.0.0.0/0からアクセス許可 |
| FAULT-SEC-04 | セキュリティ | High | network_security_groups.tf | DB IngressがコンテナNSG限定でない |
| FAULT-LB-01 | 可用性 | High | load_balancer.tf | 単一サブネットのみ |
| FAULT-LB-02 | 設定 | High | load_balancer.tf | ヘルスチェックパス不正(/api/healthcheck) |
| FAULT-LB-03 | 設定 | Critical | load_balancer.tf | バックエンドポート不一致(8080 vs 80) |
| FAULT-LB-04 | 運用 | Medium | load_balancer.tf | アクセスログ無効 |
| FAULT-CI-01 | パフォーマンス | High | container_instances.tf | OCPU/メモリ不足(1 OCPU / 1GB) |
| FAULT-CI-02 | 可用性 | High | container_instances.tf | 単一インスタンスのみ（冗長性なし） |
| FAULT-CI-03 | 設定 | Critical | container_instances.tf | コンテナポート(80)とLBバックエンドポート(8080)不一致 |
| FAULT-CI-04 | 運用 | Medium | container_instances.tf | ログ設定欠落 |
| FAULT-CI-05 | ネットワーク | Medium | container_instances.tf | パブリックIP未割当（直接アクセス不可） |
| FAULT-DB-01 | 可用性 | High | database.tf | HA無効（単一ノード、リージョナル耐久性なし） |
| FAULT-DB-02 | セキュリティ | Critical | database.tf | パブリックサブネットに配置 |
| FAULT-DB-03 | セキュリティ | High | database.tf | カスタマー管理キー未使用 |
| FAULT-DB-04 | 可用性 | Critical | database.tf | 自動バックアップ無効(NONE) |
| FAULT-DB-05 | セキュリティ | Critical | database.tf | パスワードがvariableデフォルトにハードコード |
| FAULT-DB-06 | 運用 | High | database.tf | 削除保護なし(prevent_destroy未設定) |

---

## 障害の性質について

### デプロイ可能だが問題がある障害

すべての障害は以下の条件を満たしています：

1. **`terraform plan` が成功する** - 構文・参照エラーなし
2. **`terraform apply` が成功する** - APIバリデーション通過、リソース作成完了
3. **運用上の問題が残る** - サービスが正常動作しない、セキュリティリスクがある

この設計により、DevOps Agentは「デプロイ可能なコードの中に潜む問題」を
静的解析で検知する能力をテストできます。

---

## 詳細説明

### ネットワーク障害

#### FAULT-NET-01: NATゲートウェイなし
- **ファイル**: `vcn.tf`
- **重大度**: High
- **デプロイ影響**: なし（リソース作成は成功）
- **運用影響**: プライベートサブネットのリソースがインターネットにアクセスできない。将来プライベートサブネットにコンテナを移動した場合にイメージPull失敗。
- **期待される検知**: 「プライベートサブネットにNATゲートウェイまたはサービスゲートウェイが設定されていません」

#### FAULT-NET-02: 単一AD/FDのみにパブリックサブネット
- **ファイル**: `vcn.tf`
- **重大度**: High
- **デプロイ影響**: なし
- **運用影響**: ロードバランサーの可用性が単一ADに依存。AD障害時にサービス停止。
- **期待される検知**: 「ロードバランサーに必要な複数サブネット（異なるAD）が存在しません」

---

### セキュリティ障害

#### FAULT-SEC-01: LB NSGが全プロトコル・全ポート開放
- **ファイル**: `network_security_groups.tf`
- **重大度**: High
- **デプロイ影響**: なし
- **運用影響**: ロードバランサーが全プロトコル・全ポートで外部トラフィックを受け入れる。攻撃対象面の拡大。
- **期待される検知**: 「NSGが0.0.0.0/0から全プロトコル・全ポートへのアクセスを許可しています」

#### FAULT-SEC-02: コンテナNSGのIngressポート不一致
- **ファイル**: `network_security_groups.tf`
- **重大度**: Critical
- **デプロイ影響**: なし（NSGルール自体は作成成功）
- **運用影響**: NSGがポート8080のみ許可だが、nginxはポート80でリッスン。LBからコンテナへのトラフィックがNSGでブロックされる。
- **期待される検知**: 「コンテナNSGのIngressポート(8080)がコンテナのリッスンポート(80)と一致しません」

#### FAULT-SEC-03: DB NSGが0.0.0.0/0許可
- **ファイル**: `network_security_groups.tf`
- **重大度**: Critical
- **デプロイ影響**: なし
- **運用影響**: データベースポート(5432)がインターネットから直接アクセス可能。データ漏洩リスク。
- **期待される検知**: 「DB用NSGがパブリックCIDR(0.0.0.0/0)からのPostgreSQLアクセスを許可しています」

#### FAULT-SEC-04: DB IngressがコンテナNSG限定でない
- **ファイル**: `network_security_groups.tf`
- **重大度**: High
- **デプロイ影響**: なし
- **運用影響**: DBへのアクセスを特定のNSG（コンテナ）に限定していない。最小権限原則に反する。
- **期待される検知**: 「DB NSGのソースがCIDRブロック(0.0.0.0/0)です。コンテナNSGに限定すべきです」

---

### Load Balancer障害

#### FAULT-LB-01: 単一サブネットのみ
- **ファイル**: `load_balancer.tf`
- **重大度**: High
- **デプロイ影響**: なし（OCI LBは単一サブネットでも作成可能）
- **運用影響**: 単一ADのサブネットのみ。ADレベルの障害時にLBが影響を受ける。
- **期待される検知**: 「ロードバランサーに1つのサブネットのみが指定されています」

#### FAULT-LB-02: ヘルスチェックパス不正
- **ファイル**: `load_balancer.tf`
- **重大度**: High
- **デプロイ影響**: なし（ヘルスチェック設定は構文上有効）
- **運用影響**: ヘルスチェックが`/api/healthcheck`を確認するが、nginxは`/`で応答。バックエンドが常にunhealthyになる。
- **期待される検知**: 「ヘルスチェックパスがアプリケーションの実際のエンドポイントと一致しない可能性」

#### FAULT-LB-03: バックエンドポート不一致
- **ファイル**: `load_balancer.tf`
- **重大度**: Critical
- **デプロイ影響**: なし（ポート番号は有効な値）
- **運用影響**: LBがポート8080にトラフィック転送するが、nginxはポート80。接続拒否。
- **期待される検知**: 「バックエンドポート(8080)がコンテナのリッスンポート(80)と一致しません」

#### FAULT-LB-04: アクセスログ無効
- **ファイル**: `load_balancer.tf`
- **重大度**: Medium
- **デプロイ影響**: なし
- **運用影響**: リクエストの監査証跡なし。障害時のトラブルシューティング困難。
- **期待される検知**: 「ロードバランサーのアクセスログが有効化されていません」

---

### Container Instance障害

#### FAULT-CI-01: OCPU/メモリ不足
- **ファイル**: `container_instances.tf`
- **重大度**: High
- **デプロイ影響**: なし（1 OCPU / 1GBは有効な値）
- **運用影響**: リソース不足でOOMKill発生の可能性。本番ワークロードには不十分。
- **期待される検知**: 「コンテナインスタンスのメモリ(1GB)が不十分な可能性があります」

#### FAULT-CI-02: 単一インスタンスのみ
- **ファイル**: `container_instances.tf`
- **重大度**: High
- **デプロイ影響**: なし
- **運用影響**: 単一インスタンスの障害でサービス停止。冗長性なし。
- **期待される検知**: 「コンテナインスタンスが1つのみです。冗長性がありません」

#### FAULT-CI-03: コンテナポートとLBバックエンドポート不一致
- **ファイル**: `container_instances.tf`
- **重大度**: Critical
- **デプロイ影響**: なし
- **運用影響**: nginx(ポート80)にLB(ポート8080)から到達不能。サービス応答なし。
- **期待される検知**: 「コンテナポート、LBバックエンドポート、NSGポートが不整合です」

#### FAULT-CI-04: ログ設定欠落
- **ファイル**: `container_instances.tf`
- **重大度**: Medium
- **デプロイ影響**: なし
- **運用影響**: アプリケーションログが収集されず、障害解析不能。
- **期待される検知**: 「コンテナインスタンスにOCI Loggingの設定がありません」

#### FAULT-CI-05: パブリックIP未割当
- **ファイル**: `container_instances.tf`
- **重大度**: Medium
- **デプロイ影響**: なし
- **運用影響**: コンテナに直接SSHやデバッグアクセスできない（LB経由のみ）。
- **期待される検知**: 「コンテナインスタンスにパブリックIPが割り当てられていません」

---

### Database障害

#### FAULT-DB-01: HA無効（単一ノード）
- **ファイル**: `database.tf`
- **重大度**: High
- **デプロイ影響**: なし（instance_count=1は有効）
- **運用影響**: 単一ノード障害でDB停止。リージョナル耐久性なし。
- **期待される検知**: 「DB Systemのinstance_countが1でリージョナル耐久性が無効です」

#### FAULT-DB-02: パブリックサブネットに配置
- **ファイル**: `database.tf`
- **重大度**: Critical
- **デプロイ影響**: なし
- **運用影響**: DBがパブリックサブネットに配置。NSGと合わせてインターネットから直接アクセス可能。
- **期待される検知**: 「DB Systemがパブリックサブネットに配置されています」

#### FAULT-DB-03: カスタマー管理キー未使用
- **ファイル**: `database.tf`
- **重大度**: High
- **デプロイ影響**: なし
- **運用影響**: デフォルト暗号化のみ。コンプライアンス要件未充足の可能性。
- **期待される検知**: 「DB SystemにOCI Vault KMSキーが設定されていません」

#### FAULT-DB-04: 自動バックアップ無効
- **ファイル**: `database.tf`
- **重大度**: Critical
- **デプロイ影響**: なし（kind="NONE"は有効な設定）
- **運用影響**: データ損失時に復旧不能。ポイントインタイムリカバリ不可。
- **期待される検知**: 「DB Systemのバックアップポリシーが'NONE'です」

#### FAULT-DB-05: パスワードがvariableデフォルトにハードコード
- **ファイル**: `database.tf` / `variables.tf`
- **重大度**: Critical
- **デプロイ影響**: なし（パスワード要件は満たしている）
- **運用影響**: パスワードがソースコード内に平文保存。バージョン管理経由で漏洩リスク。
- **期待される検知**: 「パスワードがTerraform変数のデフォルト値にハードコードされています」

#### FAULT-DB-06: 削除保護なし
- **ファイル**: `database.tf`
- **重大度**: High
- **デプロイ影響**: なし
- **運用影響**: `terraform destroy`で本番DBが即座に削除される可能性。
- **期待される検知**: 「DB Systemにlifecycle prevent_destroyが設定されていません」

---

## 検知レベルの期待値

### 必須検知（Critical - 7件）
DevOps Agentが**必ず検知すべき**障害：
- FAULT-SEC-02: NSGポート不一致（サービス通信断）
- FAULT-SEC-03: DB NSGパブリック公開
- FAULT-LB-03: LBバックエンドポート不一致
- FAULT-CI-03: コンテナ/LB/NSGポート不整合
- FAULT-DB-02: DBパブリックサブネット配置
- FAULT-DB-04: バックアップ無効
- FAULT-DB-05: パスワードハードコード

### 推奨検知（High - 10件）
検知が**強く期待される**障害：
- FAULT-NET-01: NATゲートウェイなし
- FAULT-NET-02: 単一サブネット可用性
- FAULT-SEC-01: NSG全開放
- FAULT-SEC-04: DBソース未限定
- FAULT-LB-01: LB単一サブネット
- FAULT-LB-02: ヘルスチェックパス不正
- FAULT-CI-01: リソース不足
- FAULT-CI-02: 冗長性なし
- FAULT-DB-01: HA無効
- FAULT-DB-03: KMSなし
- FAULT-DB-06: 削除保護なし

### オプション検知（Medium - 4件）
検知できると**なお良い**障害：
- FAULT-LB-04: アクセスログ無効
- FAULT-CI-04: ログ設定欠落
- FAULT-CI-05: パブリックIP未割当

---

## スコアリング

| 検知数 | 評価 |
|--------|------|
| 18-21 | Excellent - 全障害を網羅的に検知 |
| 14-17 | Good - 主要な障害を検知 |
| 10-13 | Fair - 基本的な障害を検知 |
| 6-9 | Poor - 一部のみ検知 |
| 0-5 | Insufficient - 検知能力が不十分 |

---

## デプロイ手順

```bash
# 初期化
terraform init

# 変数ファイル作成（必須）
cat > terraform.tfvars <<EOF
tenancy_ocid   = "ocid1.tenancy.oc1..actual-tenancy-ocid"
compartment_id = "ocid1.compartment.oc1..actual-compartment-ocid"
oci_region     = "ap-tokyo-1"
EOF

# プラン確認（全リソースが作成されることを確認）
terraform plan

# デプロイ（全リソース正常作成される）
terraform apply -auto-approve

# 後片付け
terraform destroy -auto-approve
```

## 期待される動作

デプロイ後の状態：
- ✅ VCN / サブネット / ルートテーブル作成成功
- ✅ NSG / NSGルール作成成功
- ✅ Load Balancer作成成功
- ✅ Container Instance作成成功（nginx起動）
- ✅ PostgreSQL DB System作成成功
- ❌ LB → コンテナへのヘルスチェック失敗（ポート/パス不一致）
- ❌ エンドユーザーからのリクエストがコンテナに到達しない
- ❌ DBがインターネットから直接アクセス可能な状態
