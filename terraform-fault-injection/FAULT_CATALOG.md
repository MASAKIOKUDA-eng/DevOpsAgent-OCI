# 障害カタログ - DevOps Agent 検知テスト (OCI版)

このドキュメントは、Terraformコードに注入されたすべての障害と、
DevOps Agentが検知すべき期待される結果をまとめたものです。

---

## 障害サマリ

| ID | カテゴリ | 重大度 | ファイル | 概要 |
|----|---------|--------|---------|------|
| FAULT-NET-01 | ネットワーク | Critical | vcn.tf | NATゲートウェイなし |
| FAULT-NET-02 | 可用性 | Critical | vcn.tf | 単一AD/FDのみにパブリックサブネット |
| FAULT-NET-03 | ネットワーク | High | vcn.tf | パブリックルートテーブルにIGWルートなし |
| FAULT-SEC-01 | セキュリティ | High | network_security_groups.tf | LB NSGが全ポート開放 |
| FAULT-SEC-02 | 設定 | Critical | network_security_groups.tf | コンテナNSGのポート不一致 |
| FAULT-SEC-03 | セキュリティ | Critical | network_security_groups.tf | DB NSGが0.0.0.0/0許可 |
| FAULT-SEC-04 | ネットワーク | High | network_security_groups.tf | コンテナ→DB通信不許可 |
| FAULT-LB-01 | 可用性 | Critical | load_balancer.tf | 単一サブネットのみ |
| FAULT-LB-02 | 設定 | High | load_balancer.tf | ヘルスチェックパス不正 |
| FAULT-LB-03 | 設定 | Critical | load_balancer.tf | バックエンドセットポート不一致 |
| FAULT-LB-04 | 運用 | Medium | load_balancer.tf | アクセスログ無効 |
| FAULT-CI-01 | パフォーマンス | High | container_instances.tf | OCPU/メモリ不足 |
| FAULT-CI-02 | 可用性 | High | container_instances.tf | 単一インスタンスのみ |
| FAULT-CI-03 | 設定 | Critical | container_instances.tf | コンテナポート不一致 |
| FAULT-CI-04 | 運用 | Medium | container_instances.tf | ログ設定欠落 |
| FAULT-CI-05 | セキュリティ | Critical | container_instances.tf | OCIR Pull権限なし |
| FAULT-DB-01 | 可用性 | High | database.tf | HA無効（単一ノード） |
| FAULT-DB-02 | セキュリティ | Critical | database.tf | パブリックサブネットに配置 |
| FAULT-DB-03 | セキュリティ | High | database.tf | カスタマー管理キー未使用 |
| FAULT-DB-04 | 可用性 | Critical | database.tf | 自動バックアップ無効 |
| FAULT-DB-05 | セキュリティ | Critical | database.tf | パスワードハードコード |
| FAULT-DB-06 | 運用 | High | database.tf | 削除保護なし |

---

## 詳細説明

### ネットワーク障害

#### FAULT-NET-01: NATゲートウェイなし
- **ファイル**: `vcn.tf`
- **重大度**: Critical
- **影響**: プライベートサブネットからインターネットアクセス不可。コンテナインスタンスがOCIR（Oracle Cloud Infrastructure Registry）からコンテナイメージをPullできない。
- **期待される検知**: 「プライベートサブネットにNATゲートウェイまたはサービスゲートウェイが設定されていません」
- **修正方法**: `oci_core_nat_gateway`の追加、またはOCIサービスゲートウェイの作成

#### FAULT-NET-02: 単一AD/FDのみにパブリックサブネット
- **ファイル**: `vcn.tf`
- **重大度**: Critical
- **影響**: ロードバランサーの可用性が単一障害点に依存。AD障害時にサービス全体が停止。
- **期待される検知**: 「ロードバランサーに必要な複数サブネット（異なるAD/FD）が存在しません」
- **修正方法**: 別のAD/FDにパブリックサブネットを追加

#### FAULT-NET-03: パブリックルートテーブルにIGWルートなし
- **ファイル**: `vcn.tf`
- **重大度**: High
- **影響**: パブリックサブネットからインターネットへのルートがなく、ロードバランサーが外部アクセスを受け付けられない。
- **期待される検知**: 「パブリックサブネットのルートテーブルにインターネットゲートウェイへのルートが設定されていません」
- **修正方法**: `oci_core_route_table`にIGWへの`route_rules`を追加

---

### セキュリティ障害

#### FAULT-SEC-01: LB NSGが全ポート開放
- **ファイル**: `network_security_groups.tf`
- **重大度**: High
- **影響**: ロードバランサーが全ポートで外部からのトラフィックを受け入れる。攻撃対象領域の拡大。
- **期待される検知**: 「NSGが0.0.0.0/0から全プロトコル・全ポートへのアクセスを許可しています」
- **修正方法**: HTTP(80)とHTTPS(443)のTCPのみに制限

#### FAULT-SEC-02: コンテナNSGのポート不一致
- **ファイル**: `network_security_groups.tf`
- **重大度**: Critical
- **影響**: LBからコンテナへの通信が到達不能。サービスが応答しない。
- **期待される検知**: 「コンテナNSGのIngressポート(8080)がコンテナポート(3000)と一致しません」
- **修正方法**: NSGのポートをコンテナポート3000に修正

#### FAULT-SEC-03: DB NSGが0.0.0.0/0許可
- **ファイル**: `network_security_groups.tf`
- **重大度**: Critical
- **影響**: データベースがインターネットから直接アクセス可能。データ漏洩リスク。
- **期待される検知**: 「DB用NSGがパブリックアクセス(0.0.0.0/0)を許可しています」
- **修正方法**: コンテナNSGからのアクセスのみに制限

#### FAULT-SEC-04: コンテナ→DB通信不許可
- **ファイル**: `network_security_groups.tf`
- **重大度**: High
- **影響**: コンテナからDBへの接続が確立できない。アプリケーションがDB接続エラーを返す。
- **期待される検知**: 「コンテナインスタンスからDBへのPostgreSQL(5432)通信がNSGで許可されていません」
- **修正方法**: DB NSGにコンテナNSGからのポート5432 Ingressルールを追加

---

### Load Balancer障害

#### FAULT-LB-01: 単一サブネットのみ
- **ファイル**: `load_balancer.tf`
- **重大度**: Critical
- **影響**: ロードバランサーの可用性が単一サブネット・単一ADに依存。AD障害時にサービス停止。
- **期待される検知**: 「ロードバランサーに1つのサブネットのみが指定されています。複数ADへの配置を推奨します」
- **修正方法**: 2つ目のADにサブネットを追加し、subnet_idsに含める

#### FAULT-LB-02: ヘルスチェックパス不正
- **ファイル**: `load_balancer.tf`
- **重大度**: High
- **影響**: ヘルスチェックが常に失敗し、バックエンドがunhealthyになる。トラフィックが転送されない。
- **期待される検知**: 「ヘルスチェックパス(/api/healthcheck)がアプリケーションの実際のエンドポイントと一致しない可能性があります」
- **修正方法**: アプリケーションの実際のヘルスチェックエンドポイント(/health)に修正

#### FAULT-LB-03: バックエンドセットポート不一致
- **ファイル**: `load_balancer.tf`
- **重大度**: Critical
- **影響**: LBがポート8080にトラフィックを転送するが、コンテナはポート3000でリッスン。
- **期待される検知**: 「バックエンドのポート(8080)がコンテナのリッスンポート(3000)と一致しません」
- **修正方法**: バックエンドのポートを3000に修正

#### FAULT-LB-04: アクセスログ無効
- **ファイル**: `load_balancer.tf`
- **重大度**: Medium
- **影響**: リクエストの監査証跡がなく、障害時のトラブルシューティングが困難。
- **期待される検知**: 「ロードバランサーのアクセスログが有効化されていません」
- **修正方法**: OCI Loggingサービスとの連携を設定

---

### Container Instance障害

#### FAULT-CI-01: OCPU/メモリ不足
- **ファイル**: `container_instances.tf`
- **重大度**: High
- **影響**: アプリケーションがリソース不足でOOMKillまたはCPUスロットリング。メモリ1GBはNode.jsアプリには不十分。
- **期待される検知**: 「コンテナインスタンスのメモリ(1GB)がアプリケーション要件を満たしていない可能性があります」
- **修正方法**: memory_in_gbs=2以上に設定

#### FAULT-CI-02: 単一インスタンスのみ
- **ファイル**: `container_instances.tf`
- **重大度**: High
- **影響**: 単一インスタンスの障害でサービス全体が停止。冗長性がない。
- **期待される検知**: 「コンテナインスタンスが1つのみです。冗長性がありません」
- **修正方法**: 複数インスタンスの作成、またはOKE (Kubernetes)への移行

#### FAULT-CI-03: コンテナポート不一致
- **ファイル**: `container_instances.tf`
- **重大度**: Critical
- **影響**: コンテナポート(3000)、バックエンドポート(8080)、NSGポート(8080)が整合していない。
- **期待される検知**: 「コンテナポート、バックエンドポート、NSGのIngressポートが整合していません」
- **修正方法**: 全てをコンテナポート3000に統一

#### FAULT-CI-04: ログ設定欠落
- **ファイル**: `container_instances.tf`
- **重大度**: Medium
- **影響**: アプリケーションログが取得されず、障害時のデバッグが不可能。
- **期待される検知**: 「コンテナインスタンスにOCI Loggingの設定がされていません」
- **修正方法**: OCI Loggingサービスとの連携を設定

#### FAULT-CI-05: OCIR Pull権限なし
- **ファイル**: `container_instances.tf`
- **重大度**: Critical
- **影響**: コンテナインスタンスがOCIRからイメージをPullできず、起動に失敗する。
- **期待される検知**: 「コンテナインスタンスにOCIR Pull用のイメージPullシークレットまたはIAMポリシーが設定されていません」
- **修正方法**: ダイナミックグループとIAMポリシーの追加、またはimage_pull_secretsの設定

---

### Database障害

#### FAULT-DB-01: HA無効（単一ノード）
- **ファイル**: `database.tf`
- **重大度**: High
- **影響**: 単一ノードの障害でデータベースが停止。フェイルオーバー不可。
- **期待される検知**: 「DB Systemのinstance_countが1です。高可用性が無効です」
- **修正方法**: instance_count=2以上に設定し、リージョナル耐久性を有効化

#### FAULT-DB-02: パブリックサブネットに配置
- **ファイル**: `database.tf`
- **重大度**: Critical
- **影響**: データベースがパブリックサブネットに配置され、NSGと組み合わさるとインターネットから直接アクセス可能。
- **期待される検知**: 「DB Systemがパブリックサブネットに配置されています」
- **修正方法**: プライベートサブネット(private_ad1)に配置を変更

#### FAULT-DB-03: カスタマー管理キー未使用
- **ファイル**: `database.tf`
- **重大度**: High
- **影響**: デフォルト暗号化のみ。カスタマー管理キーによる暗号化制御ができず、コンプライアンス要件を満たさない可能性。
- **期待される検知**: 「DB Systemにカスタマー管理キー(OCI Vault KMS)が設定されていません」
- **修正方法**: OCI Vault KMSキーを作成し、kms_key_idに指定

#### FAULT-DB-04: 自動バックアップ無効
- **ファイル**: `database.tf`
- **重大度**: Critical
- **影響**: データ損失時に復旧不能。ポイントインタイムリカバリが使用できない。
- **期待される検知**: 「DB Systemのバックアップポリシーが'NONE'です。自動バックアップが無効です」
- **修正方法**: backup_policyのkindを"DAILY"に設定し、retention_daysを7以上に設定

#### FAULT-DB-05: パスワードハードコード
- **ファイル**: `database.tf`
- **重大度**: Critical
- **影響**: パスワードがソースコードに平文で保存。バージョン管理システムを通じて漏洩リスク。
- **期待される検知**: 「DB Systemのパスワードがプレーンテキストでハードコードされています」
- **修正方法**: OCI Vaultのシークレットを使用（password_type = "VAULT_SECRET"）

#### FAULT-DB-06: 削除保護なし
- **ファイル**: `database.tf`
- **重大度**: High
- **影響**: terraform destroyや誤操作で本番DBが削除される可能性。
- **期待される検知**: 「DB Systemに削除保護が設定されていません」
- **修正方法**: lifecycleブロックでprevent_destroy = trueを設定、またはIAMポリシーで制限

---

## 検知レベルの期待値

### 必須検知（Critical）
DevOps Agentが**必ず検知すべき**障害：
- FAULT-NET-01, FAULT-NET-02
- FAULT-SEC-02, FAULT-SEC-03
- FAULT-LB-01, FAULT-LB-03
- FAULT-CI-03, FAULT-CI-05
- FAULT-DB-02, FAULT-DB-04, FAULT-DB-05

### 推奨検知（High）
検知が**強く期待される**障害：
- FAULT-NET-03
- FAULT-SEC-01, FAULT-SEC-04
- FAULT-LB-02
- FAULT-CI-01, FAULT-CI-02
- FAULT-DB-01, FAULT-DB-03, FAULT-DB-06

### オプション検知（Medium）
検知できると**なお良い**障害：
- FAULT-LB-04
- FAULT-CI-04

---

## スコアリング

| 検知数 | 評価 |
|--------|------|
| 18-22 | Excellent - 全障害を網羅的に検知 |
| 14-17 | Good - 主要な障害を検知 |
| 10-13 | Fair - 基本的な障害を検知 |
| 6-9 | Poor - 一部のみ検知 |
| 0-5 | Insufficient - 検知能力が不十分 |
