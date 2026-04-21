.PHONY: db-up db-down app-up app-down

# データベースの起動と停止を定義
db-up:
	docker compose -f compose.db.yaml up -d

db-down:
	docker compose -f compose.db.yaml down

# アプリケーション（本番同等）の起動と停止を定義
app-up:
	docker compose -f compose.app.yaml up -d

app-down:
	docker compose -f compose.app.yaml down

attend-image:
	docker save -o attendance-management.tar attendance-management:0.0.1

attend-load:
	docker load -i attendance-management.tar
