# KadoZero Messenger 仕様書 (LINE 風拡張)

本ドキュメントは、現行の単一画面チャット (AI 通訳機能のみ) を LINE 風のメッセンジャーへ拡張するための実装仕様である。Codex に渡して実装させる前提で、画面・API・データモデル・セキュリティ要件を網羅的に記述する。

- 既存仕様 (`docs/product-spec.md`, `docs/api-spec.md`) は本仕様の土台。AI 通訳 (`POST /v1/messages/analyze`) は **送信前フィルタ** として全 DM / グループ送信フローに組み込む。
- クライアント : iOS / SwiftUI (`@Observable`, `async/await`, **Combine 不使用**)
- サーバー : 既存 FastAPI を拡張。永続化 DB を新規導入。
- 対象 OS : iOS 17 以降。
- 想定スケール : MVP は数百〜数千ユーザ程度。将来 E2EE 対応を見据えた設計を取るが MVP では TLS + サーバ側暗号化に留める。

---

## 1. スコープと優先順位

### 1.1 機能スコープ (MVP)

| # | 機能 | 優先度 | 備考 |
|---|---|---|---|
| F1 | サインアップ / ログイン (メール + パスワード) | P0 | Apple Sign In は P1 |
| F2 | 友だち追加 (ユーザ ID / QR コード) | P0 | |
| F3 | 友だち一覧 | P0 | |
| F4 | DM (1:1 トーク) | P0 | 送信前に AI 通訳フィルタ |
| F5 | チャット一覧 (DM + グループ統合) | P0 | 最新メッセージ + 未読バッジ |
| F6 | グループチャット (作成 / 参加 / 退出) | P0 | 最大 100 人 |
| F7 | 既読 / 未読管理 | P1 | |
| F8 | プッシュ通知 (APNs) | P1 | |
| F9 | 画像送信 | P2 | S3 互換ストレージ |
| F10 | E2EE (Signal Protocol 風) | P3 | 将来拡張、本仕様では設計だけ示す |

### 1.2 非機能要件

- TLS 1.2+ 強制。HTTP 平文不許可。
- API レイテンシ p95 < 400ms (通訳呼び出しを除く)。
- メッセージ送達は **At-least-once**。クライアント側で `client_message_id` を用いて冪等処理。
- WebSocket でリアルタイム配信。再接続時は差分同期。

---

## 2. 全体アーキテクチャ

```
┌──────────────────┐      HTTPS / WSS       ┌────────────────────┐
│   iOS App        │ ─────────────────────▶ │  FastAPI Backend   │
│  (SwiftUI)       │ ◀───────────────────── │  + WebSocket Hub   │
└─────────┬────────┘                        └─────┬──────────────┘
          │ Keychain                              │
          │ SwiftData (local cache)               ├─▶ PostgreSQL (主データ)
          │                                       ├─▶ Redis (presence / pubsub)
          │                                       ├─▶ Gemini API (AI 通訳)
          │                                       └─▶ S3 互換 (画像, 将来)
```

- 認証は **アクセストークン (短命 JWT, 15 分) + リフレッシュトークン (長命, 30 日, 回転式)** の二段構え。
- リアルタイム配信は WebSocket (`/v1/ws`)。ペイロードはサーバ確定後のメッセージのみ流す。
- AI 通訳は **送信前** に必ず通す (DM / グループ問わず)。送信ボタン → analyze → ユーザ確認 → 確定送信 の順。

---

## 3. データモデル

### 3.1 サーバー DB (PostgreSQL)

```sql
-- ユーザ
CREATE TABLE users (
  id            UUID PRIMARY KEY,
  handle        VARCHAR(32)  UNIQUE NOT NULL,    -- 友だち追加用の公開ID (例: @yuto_n)
  display_name  VARCHAR(64)  NOT NULL,
  email         VARCHAR(255) UNIQUE NOT NULL,
  password_hash TEXT         NOT NULL,           -- Argon2id
  avatar_url    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ                       -- 論理削除
);

-- リフレッシュトークン (回転式・失効管理)
CREATE TABLE refresh_tokens (
  id           UUID PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash   TEXT NOT NULL,                    -- SHA-256(token)
  device_id    TEXT NOT NULL,
  expires_at   TIMESTAMPTZ NOT NULL,
  revoked_at   TIMESTAMPTZ
);
CREATE INDEX ON refresh_tokens(user_id);

-- 友だち関係 (双方向。承認モデルにする場合は status を導入)
CREATE TABLE friendships (
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, friend_id),
  CHECK (user_id <> friend_id)
);

-- 会話 (DM / グループ共通)
CREATE TABLE conversations (
  id          UUID PRIMARY KEY,
  kind        VARCHAR(8) NOT NULL CHECK (kind IN ('dm','group')),
  title       VARCHAR(64),                       -- group のみ
  created_by  UUID NOT NULL REFERENCES users(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 参加者
CREATE TABLE conversation_members (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role            VARCHAR(8) NOT NULL DEFAULT 'member' CHECK (role IN ('owner','admin','member')),
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_read_at    TIMESTAMPTZ,                  -- 既読カーソル
  muted           BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (conversation_id, user_id)
);

-- メッセージ
CREATE TABLE messages (
  id                 UUID PRIMARY KEY,
  conversation_id    UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id          UUID NOT NULL REFERENCES users(id),
  client_message_id  UUID NOT NULL,             -- 冪等性用
  body               TEXT NOT NULL,             -- 確定後の本文 (通訳適用後)
  original_body      TEXT,                       -- 通訳前 (任意。保存ポリシー次第)
  kind               VARCHAR(16) NOT NULL DEFAULT 'text',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at         TIMESTAMPTZ,
  UNIQUE (conversation_id, client_message_id)
);
CREATE INDEX ON messages(conversation_id, created_at DESC);
```

### 3.2 クライアント永続化 (SwiftData)

| エンティティ | 用途 | 保存場所 |
|---|---|---|
| `UserProfile` | 自分のプロフィール (id, handle, display_name) | SwiftData |
| `Friend` | 友だち一覧キャッシュ | SwiftData |
| `Conversation` | 会話メタ + 最新メッセージ + 未読数 | SwiftData |
| `Message` | メッセージ本体 (送信中/送信済/失敗 状態を持つ) | SwiftData |
| `AccessToken` | JWT 本体 | Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) |
| `RefreshToken` | リフレッシュトークン | Keychain (同上、`access=AfterFirstUnlock`) |

- SwiftData にはメッセージ本文を **平文で保存** (端末暗号化に依存)。後述 §7 のデータ保持方針を参照。
- ログアウト時は SwiftData ストアを完全削除し Keychain のトークンも消す。

---

## 4. API 仕様

すべてのエンドポイントは `https://<host>/v1` 配下。`Content-Type: application/json`。認証が必要なエンドポイントは `Authorization: Bearer <access_token>`。

### 4.1 認証系

| Method | Path | 概要 |
|---|---|---|
| POST | `/auth/signup` | サインアップ。`{email, password, display_name, handle}` → `{user, access_token, refresh_token}` |
| POST | `/auth/login` | ログイン。`{email, password, device_id}` → `{access_token, refresh_token}` |
| POST | `/auth/refresh` | リフレッシュトークン回転。`{refresh_token}` → `{access_token, refresh_token}` |
| POST | `/auth/logout` | 現デバイスのリフレッシュトークンを失効 |
| GET  | `/auth/me` | 現在のユーザ情報 |

#### パスワード要件
- 10 文字以上、文字種 2 種以上。
- サーバ側で **Argon2id** によりハッシュ化 (`time_cost=3, memory=64MB, parallelism=4`)。
- ログイン失敗は IP + email 単位でレートリミット (5 回 / 5 分 でロックアウト 10 分)。

### 4.2 友だち系

| Method | Path | 概要 |
|---|---|---|
| GET  | `/friends` | 友だち一覧 |
| POST | `/friends` | `{handle}` で友だち追加 (双方向で 1 レコードずつ自動作成、もしくは承認制) |
| DELETE | `/friends/{user_id}` | 友だち削除 |
| GET  | `/users/search?handle=...` | ハンドル検索 (前方一致, レート制限 30 req/min) |

### 4.3 会話 / メッセージ

| Method | Path | 概要 |
|---|---|---|
| GET    | `/conversations` | 自分が参加する会話一覧 (DM + group)。`?cursor=...&limit=30` |
| POST   | `/conversations` | 会話作成。`{kind:"dm"\|"group", member_ids:[...], title?}`。DM は同一相手で既存があれば再利用 |
| GET    | `/conversations/{id}/messages` | メッセージ取得。`?before=<message_id>&limit=50` |
| POST   | `/conversations/{id}/messages` | メッセージ送信 (後述 §4.4) |
| POST   | `/conversations/{id}/read` | 既読更新。`{last_read_message_id}` |
| POST   | `/conversations/{id}/members` | グループにメンバー追加 |
| DELETE | `/conversations/{id}/members/{user_id}` | 退出 / キック |

### 4.4 メッセージ送信フロー (AI 通訳統合)

クライアントは送信ボタン押下時に以下のステップを必ず通す:

1. `POST /v1/messages/analyze` (既存) を叩き、`suggested_text` を取得。
2. `should_review=true` ならユーザに「そのまま送る / 提案を採用 / 編集」を提示。
3. 確定文を `POST /conversations/{id}/messages` に送る。

```jsonc
// Request
{
  "client_message_id": "9b5e...-uuid",
  "body": "通訳適用後のテキスト",
  "original_body": "元テキスト (保存可否はユーザ設定に従う)",
  "kind": "text"
}
// Response 201
{
  "id": "msg_xxx",
  "conversation_id": "conv_xxx",
  "sender_id": "user_xxx",
  "body": "...",
  "created_at": "2026-05-26T12:00:00Z"
}
```

- サーバは `(conversation_id, client_message_id)` で重複検知し、二重送信は同じ既存 ID を返す。
- 送信成功後、サーバは WebSocket でルーム参加者に `message.created` イベントを配信。

### 4.5 WebSocket `/v1/ws`

- 接続時に `Sec-WebSocket-Protocol: bearer.<access_token>` で認証。
- サーバ → クライアントイベント:
  - `message.created`, `message.deleted`, `conversation.read`, `conversation.member.changed`, `presence.changed`
- クライアント → サーバは `ping` のみ (送信は HTTP POST で完結させる)。
- 30 秒ごとに ping、応答なければ再接続。再接続後は `/conversations` と `/conversations/{id}/messages?after=<last_seen>` で差分同期。

### 4.6 エラー形式

```json
{ "error": { "code": "INVALID_HANDLE", "message": "...", "details": {} } }
```
HTTP ステータスとは独立して `error.code` を文字列で定義する (UI 側で多言語化しやすくするため)。

---

## 5. クライアント画面構成

### 5.1 画面一覧

| 画面 | 主な責務 | 主要ビューモデル |
|---|---|---|
| `LaunchView` | トークン有無で `Auth` / `Main` に分岐 | `AuthSessionStore` |
| `SignUpView` / `LoginView` | 認証 | `AuthViewModel` |
| `MainTabView` | タブ : チャット / 友だち / 設定 | — |
| `ChatListView` | 会話一覧 | `ChatListViewModel` |
| `FriendListView` | 友だち一覧 + 追加 (検索 / QR) | `FriendListViewModel` |
| `ConversationView` | DM / グループ表示 + 送信 (通訳統合済) | `ConversationViewModel` |
| `GroupCreateView` | グループ作成 (メンバー選択) | `GroupCreateViewModel` |
| `GroupSettingsView` | タイトル変更, メンバー管理, 退出 | `GroupSettingsViewModel` |
| `SettingsView` | プロフィール / ログアウト / 通訳保存設定 / 全データ削除 | `SettingsViewModel` |

### 5.2 既存 `ContentView` / `ChatViewModel` の扱い

- 現行 `ContentView` の UI コンポーネント (`MessageBubble`, グロウ演出) は **`ConversationView` に再利用**。
- 現行 `ChatViewModel` は名称を `LegacyAnalyzerViewModel` 等にリネームせず、`ConversationViewModel` に発展統合する。`sendMessage` の中で analyze → confirm → POST messages の 3 段にする。
- 既存 `APIClient.analyzeMessage` はそのまま使い、`sendMessage`, `fetchConversations` などのメソッドを追加する。

### 5.3 状態管理ルール

- 各 ViewModel は `@MainActor @Observable final class`。
- 非同期処理は `async/await`。**Combine は使用しない** (CLAUDE.md 指針)。
- 認証セッションは `AuthSessionStore` を `@Environment` で注入。401 が発生したら自動でリフレッシュ → 再試行 (1 回まで)。
- WebSocket は `RealtimeClient` シングルトンが管理。受信イベントは `AsyncStream<RealtimeEvent>` でビューモデルへ流す。

---

## 6. 認証 / 認可

- アクセストークンは **JWT (HS256)**。`sub=user_id`, `exp=15min`, `jti` を含む。
- リフレッシュトークンは **不透明文字列** (32 byte random)。DB には SHA-256 ハッシュのみ保存。
- **回転式**: `/auth/refresh` を叩くたびに新しいリフレッシュトークンを発行し、旧トークンは即時失効。再利用検出 (失効済を再提示) → 該当ユーザの全トークン失効 (盗難対策)。
- 認可は会話単位。`conversation_members` に存在するユーザだけが当該会話の API / WS イベントにアクセス可能。サーバ側ミドルウェアで都度チェック。
- レートリミット : `auth/*` は IP 単位、`/users/search` はユーザ単位、`messages` 系は (user, conversation) 単位。

---

## 7. セキュリティ要件

### 7.1 通信
- HTTPS / WSS のみ。`App Transport Security` は `NSAllowsArbitraryLoads=false` を維持。
- 証明書ピンニング : MVP 後 (P2)。実装する場合は `URLSession` の `URLAuthenticationChallenge` を `RealtimeClient` / `APIClient` の delegate で評価する。

### 7.2 機密情報の置き場
- **API ベース URL** は `Info.plist` 経由 (xcconfig は `//` をコメントとして食うため URL の `://` は xcconfig に書かない。既存実装と同じ方針を踏襲)。
- アクセストークン / リフレッシュトークン : **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable=false`)。`UserDefaults` には絶対に置かない。
- パスワードは端末に保存しない。生体認証で再ログイン補助する場合も Keychain + `LAContext` の access control を利用。

### 7.3 入力検証 / インジェクション対策
- サーバ : Pydantic v2 で厳格スキーマ検証。SQL は SQLAlchemy のパラメータバインドのみ (生 SQL 文字列連結禁止)。
- メッセージ本文の最大長 : 4000 文字。
- ファイル添付 (P2) : MIME ホワイトリスト + マジックバイト検証 + ウィルススキャン (ClamAV 等)。

### 7.4 認可漏れの防止
- 全 API ハンドラに `current_user` 依存性注入を必須にし、`conversation_id` を含むパスでは `assert_member(current_user, conversation_id)` を冒頭で呼ぶ。
- WebSocket 接続時に購読対象会話を JWT のクレームでなく DB で都度検証する (権限変更を即時反映するため)。

### 7.5 ログ / 監査
- 平文メッセージはアプリログに **絶対出さない**。`print` でメッセージ本文を出力している既存コードがあれば削除する。
- 認証イベント (login 成功 / 失敗, refresh 再利用検出, パスワード変更) は監査ログに記録 (user_id, ip, user_agent, ts)。
- Gemini API キーなどシークレットは `.env` 経由のみ。`.env` は Git 追跡しない (既存 `.gitignore` に従う)。

### 7.6 将来の E2EE 設計指針 (本 MVP では未実装)
- Signal Double Ratchet を採用。
- 各ユーザは Identity Key + 複数 OneTimePreKey をサーバに登録。
- メッセージ本文はクライアント間で暗号化し、サーバは暗号文 (`ciphertext`, `header`) のみ保存。
- AI 通訳をどう両立させるかが論点。本仕様の初期版では「通訳はクライアント送信前に行い、暗号化は通訳後の確定文に対して実施する」想定で互換性を確保する。

---

## 8. データ保持方針 (重要)

### 8.1 サーバ側

| データ | 保持期間 | 削除方式 |
|---|---|---|
| メッセージ本文 (`messages.body`) | ユーザ削除リクエストか退会まで | 退会で物理削除 (CASCADE) |
| メッセージ原文 (`messages.original_body`) | デフォルト 7 日後に NULL 化 | 日次バッチで TTL クリア (誤訳学習目的のため短命) |
| アクセス / 監査ログ | 90 日 | 自動ローテーション (S3 へアーカイブ後消去) |
| リフレッシュトークン | `expires_at` 経過か revoke 後 30 日でハードデリート | バッチ |
| Gemini への入力 / 出力 | サーバ DB には保存しない | リクエスト処理後にメモリから破棄 |

- DB のディスクは **保管時暗号化** (RDS の暗号化または同等) を有効化する。
- バックアップは 7 日間、別 KMS キーで暗号化、リストア訓練を四半期に 1 回。

### 8.2 クライアント側

- メッセージは SwiftData に **直近 30 日分** までキャッシュ。それ以前は API 要求時に再取得。
- ログアウト時 : SwiftData ストア削除 + Keychain クリア + 画像キャッシュディレクトリ削除。
- 「設定 → すべてのデータを削除」を提供。実行時にサーバへ退会 API を叩き、ローカルも同じ手順で消す。
- 端末紛失を想定し、Keychain の access フラグは `ThisDeviceOnly` 系を採用 (iCloud Keychain 共有しない)。

### 8.3 「カドゼロ通訳」原文の扱い (プライバシー上の論点)

- 既定では `original_body` を 7 日後に消す (上記)。
- ユーザ設定で **「原文をサーバに送らない / 残さない」** を選択可能にする (`Settings.preserveOriginal=false`)。OFF の場合、`POST /conversations/{id}/messages` の `original_body` は省略する。
- 通訳 API 呼び出しのリクエストは Gemini に渡る都合上、利用規約・プライバシーポリシーで明示する。

---

## 9. 実装フェーズ計画

Codex への指示は以下のフェーズ単位でブランチを切ること。

1. **Phase 1 : 認証基盤**
   - DB マイグレーション (users, refresh_tokens)
   - `/auth/signup` `/auth/login` `/auth/refresh` `/auth/logout` `/auth/me`
   - クライアント : `AuthSessionStore`, `LoginView`, `SignUpView`, トークン Keychain 保管
   - 受け入れ : サインアップ → 強制ログアウト → 再ログインで状態復元できる

2. **Phase 2 : 友だち / 会話骨格**
   - DB : friendships, conversations, conversation_members, messages
   - `/friends*`, `/users/search`, `/conversations` (CRUD), `/conversations/{id}/messages` (GET/POST)
   - クライアント : `FriendListView`, `ChatListView`, `ConversationView` (既存 UI 再利用)
   - 既存 `analyzeMessage` を送信前フィルタとして統合
   - 受け入れ : 2 ユーザ間で DM を往復できる (ポーリング可)

3. **Phase 3 : リアルタイム + グループ**
   - WebSocket `/v1/ws`、Redis PubSub
   - グループ作成 / メンバー管理 / 退出
   - 既読 / 未読バッジ
   - 受け入れ : 3 人グループで送信が他 2 名に 1 秒以内に届く

4. **Phase 4 : 通知 / 強化**
   - APNs プッシュ通知 (新着メッセージのみ、ペイロードに本文を含めない or 短縮)
   - レートリミット, 監査ログ, データ削除 API
   - 受け入れ : バックグラウンドで通知受信、タップで該当会話を開ける

5. **Phase 5 (任意) : 画像送信 / E2EE 設計検証**

---

## 10. 受け入れ基準 / テスト

- ユニットテスト : `Testing` フレームワーク (既存方針)。`ConversationViewModel.send` の analyze → confirm → post の各分岐を網羅。
- UI テスト : `XCUIAutomation` でログイン → 友だち追加 → DM 送信のゴールデンパス。
- セキュリティ自動チェック (CI):
  - リフレッシュトークン再利用検出が動作する (失効後の再提示で 401 かつ全トークン無効化)。
  - 他ユーザの会話に POST / GET すると 403。
  - パスワードハッシュは Argon2id 形式 (`$argon2id$...`) で DB に保存されている。
- 手動チェックリスト :
  - ログアウト後に Keychain と SwiftData が空であることを確認 (デバッグメニューから検証コマンド)。
  - 機内モード → 復帰時に WebSocket が再接続され、未取得メッセージが補完される。
  - 「すべてのデータを削除」を実行すると、サーバ側 `users.deleted_at` が立ち、再ログイン不可。

---

## 11. オープン論点 (Codex に判断を委ねず必ず確認すべき項目)

1. 友だち追加は **承認制 / 即時** どちらにするか。本仕様は即時前提だが、承認制にする場合 `friendships.status` を追加する。
2. グループに招待リンクを発行するか (本仕様では未対応)。
3. 通訳の原文保存ポリシーの既定値 (本仕様は「7 日で削除」を既定)。
4. プッシュ通知の本文表示有無 (プライバシーと利便性のトレードオフ)。
5. ホスティング先 (Render / Fly.io / 自前 VPS) と Postgres / Redis の選定。

これらは Codex 着手前にユーザ判断を仰ぐこと。
