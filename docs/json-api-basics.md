# JSON / API 超入門メモ

## このメモの目的

Kadozero を作るうえで必要になる `JSON` と `API` の最低限を理解する。

## JSON とは

JSON は、プログラム同士がデータをやり取りするときによく使う書き方。

人間向けの文章ではなく、`データの入れ物` に近い。

例えば:

```json
{
  "message_id": "msg_001",
  "text": "お前、なんでまだやってないの？馬鹿じゃないの",
  "language": "ja",
  "recent_messages": []
}
```

## JSON の基本要素

- `{}`: オブジェクト。項目をまとめる箱
- `[]`: 配列。複数の値を並べる箱
- `"文字"`: 文字列
- `123`: 数値
- `true` / `false`: 真偽値
- `null`: 値がないことを表す

## この JSON が意味すること

```json
{
  "message_id": "msg_001",
  "conversation_id": "conv_001",
  "text": "お前、なんでまだやってないの？馬鹿じゃないの",
  "tone_preference": "gentle",
  "language": "ja",
  "recent_messages": []
}
```

- `message_id`: メッセージのID
- `conversation_id`: 会話のID
- `text`: メッセージ本文
- `tone_preference`: どんな言い換えトーンを希望するか
- `language`: 言語
- `recent_messages`: 直近の会話履歴

## API とは

API は、アプリ同士がデータをやり取りするための窓口。

Kadozero では、

- iOS アプリがクライアント
- FastAPI がサーバ

という関係になる。

## Kadozero での流れ

1. iOS アプリがメッセージを入力として持つ
2. その内容を JSON で FastAPI に送る
3. FastAPI が Gemini を使って分析する
4. FastAPI が JSON で結果を返す
5. iOS アプリがその JSON を見て画面を出し分ける

## Request と Response

- Request: クライアントがサーバに送るデータ
- Response: サーバがクライアントに返すデータ

Kadozero の例:

### Request

```json
{
  "message_id": "msg_001",
  "conversation_id": "conv_001",
  "text": "お前、なんでまだやってないの？馬鹿じゃないの",
  "tone_preference": "gentle",
  "language": "ja",
  "recent_messages": []
}
```

### Response

```json
{
  "message_id": "msg_001",
  "should_review": true,
  "severity": "high",
  "emotion": "anger",
  "detected_expressions": ["お前", "馬鹿じゃないの"],
  "original_text": "お前、なんでまだやってないの？馬鹿じゃないの",
  "suggested_text": "まだ対応できていないようなので、状況を教えてもらえますか？",
  "reasons": [
    "「お前」が強く相手を責める印象を与える可能性があります",
    "「馬鹿じゃないの」が攻撃的に受け取られる可能性があります"
  ],
  "analysis_summary": "強い否定と責める口調が含まれているため、送信前確認を推奨します。"
}
```

## この Response の意味

- `should_review`: 確認画面を出すべきか
- `severity`: 強さの程度
- `emotion`: 感情傾向
- `detected_expressions`: 問題になりそうな表現
- `original_text`: 元の文
- `suggested_text`: 提案文
- `reasons`: 理由一覧
- `analysis_summary`: 全体の短い要約

## なぜ構造化 JSON で返すのか

AI に普通の文章で返させると、毎回フォーマットがぶれやすい。

例:

```text
この文章には強い表現が含まれています。
「お前」や「馬鹿じゃないの」は攻撃的に受け取られる可能性があります。
次のように言い換えるとよいでしょう。
「まだ対応できていないようなので、状況を教えてもらえますか？」
```

これは人間には読めるが、アプリには扱いにくい。

一方で JSON なら、

- `should_review` を見て確認画面を出す
- `suggested_text` を提案欄に表示する
- `reasons` を箇条書きで出す

のように、アプリ側が安定して使える。

## HTTP の最低限

- `GET`: 取得するときによく使う
- `POST`: データを送るときによく使う

Kadozero の例:

- `GET /health`
  サーバが動いているか確認する
- `POST /v1/messages/analyze`
  メッセージを送って分析結果を受け取る

## 今の段階で理解できれば十分なこと

- JSON = データの入れ物
- API = アプリ同士の受け渡し口
- Request = 送るデータ
- Response = 返ってくるデータ

## 次に覚えるとよいキーワード

1. JSON
2. HTTP API / REST API
3. クライアント・サーバ
4. スキーマ
5. FastAPI
