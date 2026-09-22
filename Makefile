.PHONY: db-up db-down app-up app-down attend-image attend-load

# データベースの起動と停止を定義
db-up:
	docker compose -f compose.db.yaml up -d

db-down:
	docker compose -f compose.db.yaml down

# ボリューム（データ）も含めて完全に削除
db-destroy:
    docker compose -f compose.db.yaml down -v

# アプリケーション（本番同等）の起動と停止を定義
app-up:
	docker compose -f compose.app.yaml up -d

app-down:
	docker compose -f compose.app.yaml down

attend-image:
	docker save -o attendance-management.tar attendance-management:0.0.1

attend-load:
	docker load -i attendance-management.tar

# Makefile への追加提案
app-dev-up:
	docker compose -f compose.app.dev.yaml up -d

app-dev-down:
	docker compose -f compose.app.dev.yaml down

# アプリのビルド
app-build:
	docker compose -f compose.app.yaml build

# アプリのログをリアルタイム追跡
app-logs:
	docker compose -f compose.app.yaml logs -f attendance-app

# 全コンテナの稼働状況を確認
ps:
	docker ps