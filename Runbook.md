本ドキュメントは、開発者や運用保守担当者がローカル環境でゼロからシステムを立ち上げ、手動テストやバッチの動作確認を行うための手順書です。

---

## 1. 事前準備

以下のツールがローカル端末にインストールされていることを確認してください。

- **Docker & Docker Compose**: コンテナ環境の実行
- **Java 25 (Temurin等)**: ローカルでのビルドやIDE補完用
- **Make**: `Makefile` を利用したコマンド簡略化用（Windows環境の場合は WSL2 の利用を推奨）
- *(前提)* `infra/env/` 配下の各 `.env` ファイルや、LINE WORKSの秘密鍵（`infra/lineworks/*.key`）が適切なパスに配置されていること。

---

## 2. 初回セットアップ手順

### 2.1. 共有ネットワークの作成
各 `docker-compose.yaml` をまたいでコンテナ同士が通信できるよう、外部ネットワークをあらかじめ作成します。
```bash
docker network create local-app-network
```

### 2.2. インフラストラクチャ（DB / Kafka）の起動
PostgreSQL データベースおよび Kafka（KRaftモード）/ Kafka-UI を起動します。
```bash
# データベースの起動（ポート: 5432）
make db-up

# Kafka / Kafka-UI の起動（ポート: 9092, 8080）
# ※ Makefileに定義がないため、直接 docker compose コマンドを実行
docker compose -f compose.kafka.yaml up -d
```
> **💡 補足 (DBマイグレーション):**
> 初回起動時用のDBスキーマやテーブル生成は、のちほど Spring Boot アプリケーションが起動する際に Flyway によって自動実行されます。

### 2.3. アプリケーションのビルドと起動
開発用（WireMock同梱）の構成でアプリケーションを起動します。
```bash
# 両アプリケーションの Docker イメージをビルド
make app-build

# 開発用構成（compose.app.dev.yaml）で立ち上げ
make app-dev-up
```
起動完了後、以下の URL から API 仕様書（Swagger UI）にアクセスし、システムが正常稼働しているか確認できます。
* 勤怠管理サービス: http://localhost:8180/swagger-ui.html
* 通知サービス: http://localhost:8181/swagger-ui.html

---

## 3. Makefile および Docker Compose の主要コマンド一覧

リポジトリルート（`docker` ディレクトリ）で実行可能な主要な `make` コマンドです。

| コマンド | 処理内容 |
| :--- | :--- |
| `make db-up` | DB（PostgreSQL）をバックグラウンドで起動 |
| `make db-down` | DBコンテナを停止・削除（データはボリュームに保持） |
| `make db-destroy` | DBコンテナと**ボリューム（データ）を完全に削除**（初期化用） |
| `make app-build` | アプリケーションの Docker イメージを再ビルド |
| `make app-dev-up` | 開発用構成（アプリ＋WireMock）をバックグラウンドで起動 |
| `make app-dev-down` | 開発用構成のコンテナを停止・削除 |
| `make app-logs` | 勤怠管理サービス（attendance-app）のログをリアルタイム追跡 |
| `make ps` | 全コンテナの稼働ステータスと公開ポート一覧を確認 |

---

## 4. 疎通・動作確認テスト手順（curl コマンド）

定期実行バッチ（Cron）を待たずに、手動で各種処理をキックして動作確認を行う手順です。

### 4.1. 勤怠アラート手動トリガー
指定した日付で未打刻者（遅刻・打刻忘れ）を抽出し、管理者および本人（環境変数設定による）へアラートを通知します。
```bash
curl -X POST "http://localhost:8180/api/v1/attendances/alerts/unstamped?date=2026-09-27"
```
* **確認ポイント**: HTTP `200 OK` が返却され、対象者がいる場合は Kafka 経由で LINE WORKS へメッセージが届くこと。

### 4.2. 月次サマリ手動トリガー
指定した年月の勤怠集計（予定休・当欠・半休・遅延）を行い、差分があれば管理者へ通知します。
```bash
curl -X POST "http://localhost:8180/api/v1/attendances/summary/monthly?month=2026-09"
```
* **確認ポイント**: 対象月の勤怠が再計算・UPSERTされ、前回実行時から変動があった従業員のレポートのみが LINE WORKS に通知されること。

### 4.3. 通知サービス疎通確認
勤怠管理サービスを通さず、通知サービス単体の LINE WORKS 送信機能を直接テストします。
```bash
# ① 管理者チャンネル向けアラート通知テスト
curl -X POST "http://localhost:8181/api/v1/notifications/test/alert" \
     -d "message=テストアラート通知の疎通確認です。"

# ② システム管理者個人(DM)向けエラー通知テスト
curl -X POST "http://localhost:8181/api/v1/notifications/test/error" \
     -d "message=テスト障害通知の疎通確認です。"
```

---

## 5. トラブルシューティング

非同期メッセージング（Kafka）に関する問題が発生した際の調査手順です。

### 5.1. Kafka-UI でのキュー確認方法
メッセージの滞留や、流れた JSON ペイロードの中身を確認したい場合は、同梱されている **Kafka-UI** を利用します。
1. ブラウザで http://localhost:8080 にアクセスします。
2. 左側メニューの `local-cluster` > **Topics** を選択します。
3. `unstamped-alert-topic` 等のトピック名をクリックし、**Messages** タブを開きます。
4. 送信された JSON データを直接閲覧でき、アプリケーション間で正しくデータが連携されているか検証可能です。

### 5.2. DLT (Dead Letter Topic) 発生時のログ確認ポイント
メッセージの処理が指定回数（最大3回）失敗した、または不正なデータ（バリデーションエラー）が検知された場合、メッセージは自動的に **DLT (`<topic-name>-dlt`)** へ退避されます。

* **ログの確認**:
  通知サービスのログを確認してください。
  ```bash
  docker compose -f compose.app.dev.yaml logs -f notification-app | grep "DLT退避検知"
  ```
  `[DLT退避検知]` というキーワードと共に、**対象トピック、オフセット、根本原因、受信データの全体** がログ出力されます。

* **システム管理者への一次報**:
  DLT 退避が発生すると、`DltErrorHandler` が稼働しシステム管理者の LINE WORKS DM 宛てに即時エラー通知が飛びます。

* **原因究明 (Kafka ヘッダの確認)**:
  Kafka-UI から対象の DLT トピック（例: `unstamped-alert-topic-dlt`）のメッセージを開き、**Headers** タブを確認してください。Spring Kafka が付与した `springDeserializerExceptionValue` や `kafka_exception-message` の値から、型ミスマッチや JsonParseException などの具体的なエラー原因を特定できます。
