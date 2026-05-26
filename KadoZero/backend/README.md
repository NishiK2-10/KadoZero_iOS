# KadoZero FastAPI Backend

## 1. セットアップ
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 2. 起動
```bash
cd backend
source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## 3. 動作確認
```bash
curl http://127.0.0.1:8000/health
```
