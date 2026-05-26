# KadoZero 学習メモ（現状コードベース）

このメモは、現在の実装（UIとロジック分離後）だけをまとめたものです。

## 現在の到達点
- API連携は未接続のまま
- チャットUIは動作
- 入力/送信ロジックは `ChatViewModel` に分離済み
- 最小ユニットテストを追加済み

## 対象ファイル
- `KadoZero/KadoZero/ContentView.swift`
- `KadoZero/KadoZero/ChatViewModel.swift`
- `KadoZero/KadoZeroTests/KadoZeroTests.swift`

## 設計方針（実プロダクト寄り）
- `ContentView`: 表示責務（View）
- `ChatViewModel`: 状態管理と送信ロジック（ロジック層）

これにより、UI変更とロジック変更を分離でき、保守性とテスト容易性が上がる。

## ChatViewModel の責務
1. `inputText` と `messages` を管理
2. `isSendDisabled` で送信可否を提供
3. `sendMessage()` で入力検証・送信処理を実行
4. 仮の自動返信を遅延追加

### 送信処理の流れ
1. 入力文字列を trim
2. 空なら return
3. 自分メッセージを追加
4. 一定時間後に相手メッセージ（仮返信）を追加

## ContentView の責務
1. `@State` で `ChatViewModel` を保持
2. `viewModel.messages` を `ForEach` で表示
3. 新着時に最下部へ自動スクロール
4. 入力欄・送信ボタンを `viewModel` とバインド

## テスト（Testing framework）
- `sendMessage_空文字は追加されない`
- `sendMessage_送信で自分と相手の2件が追加される`

## 注意点
- ビルドは成功
- テスト実行はこの環境でキャンセルされる状態（コードは追加済み）

## 次にやること
1. 仮返信を外し、`APIClient` へ接続
2. 送信前レビューUI（提案採用/そのまま送信）を再導入
3. 履歴保存（ローカル/サーバー）を追加

---

## ステップ7：ViewModelにAPI連携を接続

### 目的
ローカル仮返信をやめて、`ChatViewModel` から `APIClient` を呼ぶ実運用寄りの流れに移行する。

### 変更ファイル
- `KadoZero/KadoZero/ChatViewModel.swift`
- `KadoZero/KadoZero/ContentView.swift`
- `KadoZero/KadoZeroTests/KadoZeroTests.swift`

### 実装内容
1. `MessageAnalyzing` プロトコルを追加し、`APIClient` を適合
2. `ChatViewModel` に `analyzer` を依存注入
3. `sendMessage()` でAPI分析を実行し、応答を相手メッセージとして追加
4. `isAnalyzing` / `errorMessage` を追加して状態を管理
5. `ContentView` で通信中表示（`ProgressView`）とエラー表示を実装
6. テストをAPIモック前提に差し替え（成功系・失敗系）

### 設計上のポイント
- Viewは表示だけ、ロジックはViewModelに集約
- API呼び出しをプロトコル化してテストしやすくする
- ネットワーク障害時もUIが破綻しないようにエラー状態を持つ

---

## ステップ8：最小FastAPIサーバーを新規作成

### 目的
iOSアプリのAPI接続先を実体化し、実機から疎通できる状態にする。

### 追加ファイル
- `KadoZero/backend/app/main.py`
- `KadoZero/backend/requirements.txt`
- `KadoZero/backend/README.md`

### 実装内容
1. `GET /health` を追加（疎通確認用）
2. `POST /v1/messages/analyze` を追加（iOSの既存リクエスト形式に対応）
3. 強い表現の簡易判定ロジックを実装（最小版）

### 起動方法
`backend/README.md` の手順で `uvicorn app.main:app --host 0.0.0.0 --port 8000` を実行。

---

## ステップ9：送信前レビューUIの再実装

### 目的
`shouldReview == true` の場合に、送信文をそのまま送るか提案文に差し替えるかをユーザーが選択できるようにする。

### 変更ファイル
- `KadoZero/KadoZero/ChatViewModel.swift`
- `KadoZero/KadoZero/ContentView.swift`
- `KadoZero/KadoZeroTests/KadoZeroTests.swift`

### 実装内容
1. ViewModelに `pendingReviewResponse` を追加
2. 送信時、レビュー必要なら即時送信せず保留状態にする
3. `acceptOriginalText` / `acceptSuggestedText` / `cancelReview` を追加
4. ContentViewにレビューシート（元文・提案文・理由・要約）を追加
5. テストにレビュー分岐のケースを追加

### 現在の挙動
- レビュー不要: そのまま会話に追加
- レビュー必要: シート表示
  - そのまま送る
  - 提案を採用
  - キャンセル

## 2026-05-26 仕様書ベースの土台実装 (MVP P0開始)
- 起動導線を `LaunchView` ベースに変更
- 認証セッション管理 `AuthSessionStore` を追加 (`launching / unauthenticated / authenticated`)
- ログイン画面 `LoginView` を追加
- メインタブ `MainTabView` を追加 (チャット / 友だち / 設定)
- チャット一覧 `ChatListView` から既存の通訳チャット画面へ遷移可能に変更
- APIクライアントに認証/会話の最小メソッドを追加
  - `login(email,password,deviceID)`
  - `me(accessToken)`
  - `fetchConversations(accessToken)`
- モデルを追加
  - `LoginRequest`, `SignupRequest`
  - `MeResponse`, `AuthResponse`
  - `ConversationSummary`
- 既存通訳チャット機能は維持しつつ、仕様書の画面構成へ寄せる第一段を完了

## 2026-05-26 新規登録画面を追加
- ログイン画面から新規登録画面へ遷移する導線を追加
- `SignUpView` を新規作成
  - 入力項目: 表示名 / ハンドル / メール / パスワード
  - ハンドルの `@` 補完を実装
  - パスワード10文字未満を送信不可に制御
- `AuthSessionStore` に `signup(...)` を追加
- `APIClient` に `POST /v1/auth/signup` 呼び出しを追加
- 登録成功時は自動で認証済み状態へ遷移

## 2026-05-26 認証エンドポイント追加（404対応）
- 新規登録で HTTP 404 になっていた原因は、FastAPI 側に `/v1/auth/signup` が未実装だったため
- `backend/app/main.py` に認証MVPエンドポイントを追加
  - `POST /v1/auth/signup`
  - `POST /v1/auth/login`
  - `GET /v1/auth/me`
- MVPとしてメモリ内ストアでユーザ/トークンを管理
- `Authorization: Bearer <token>` の検証処理を追加

## 2026-05-26 PostgreSQL永続化 + 認証セキュリティ強化
- FastAPI認証実装をメモリ保持からPostgreSQL永続化へ移行
- SQLAlchemyで `users`, `refresh_tokens` テーブルを導入
- パスワードをArgon2idでハッシュ化（平文保存を撤廃）
- アクセストークンをJWT化（短命）
- リフレッシュトークンをランダム文字列 + SHA-256ハッシュ保存 + 回転方式へ変更
- `signup / login / refresh / logout / me` エンドポイントを実装
- ハンドル形式・パスワード強度のバリデーションを追加
- `JWT_SECRET` 未設定時は起動失敗にして誤運用を防止
