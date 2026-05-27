# KadoZero

誰も傷つけない、世界一優しいチャットアプリ。
KadoZero は、1対1チャットでの送信文を Gemini でやわらかく変換し、相手に配慮した表現で届ける iOS アプリです。  
バックエンドは FastAPI + PostgreSQL で構成し、Render 上で公開運用できます。

## 主な機能

- ユーザー登録 / ログイン（JWT認証）
- 友だち追加 / 削除
- 1対1チャットルーム作成（友だち指定のみ）
- トークルーム削除
- Gemini による送信文のやわらか変換
- リフレッシュトークンによるセッション継続

## 技術スタック

- iOS: SwiftUI
- API: FastAPI (Python)
- DB: PostgreSQL
- ORM: SQLAlchemy
- Auth: JWT + Argon2
- AI: Gemini API
- Hosting: Render (Web Service + PostgreSQL)

## ディレクトリ構成

```text
KadoZero/
  KadoZero/                  # iOSアプリ本体
  backend/                   # FastAPIバックエンド
  docs/                      # 仕様・メモ
  README.md
```

## ローカル開発

### 1. Backend

```bash
cd KadoZero/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

`.env`（例）

```env
DATABASE_URL=postgresql+psycopg://<user>:<password>@127.0.0.1:5432/<db>
JWT_SECRET=<your-secret>
GEMINI_API_KEY=<your-gemini-key>
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=30
```

### 2. iOS

- `Local.xcconfig` に API URL を設定

```xcconfig
KADOZERO_API_BASE_URL = "https://kadozero-api.onrender.com"
```

`//` のコメント解釈を避けるため、URLはダブルクォートで囲みます。

## Render デプロイ

- Web Service
  - Root Directory: `KadoZero/backend`
  - Build Command: `pip install -r requirements.txt`
  - Start Command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
- 環境変数
  - `DATABASE_URL`（`postgresql+psycopg://` 形式）
  - `JWT_SECRET`
  - `GEMINI_API_KEY`
  - `ACCESS_TOKEN_EXPIRE_MINUTES=30`
  - `REFRESH_TOKEN_EXPIRE_DAYS=30`

## ライセンス

MIT

