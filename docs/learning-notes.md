# KadoZero 学習メモ（現状コードベース）

このメモは、現在の `ContentView.swift` の実装内容だけをまとめたものです。

## 現在の到達点
- API連携はまだ使わない
- ローカル状態だけでチャット画面が動く
- 送信・表示・仮返信・自動スクロールができる

## 対象ファイル
- `KadoZero/KadoZero/ContentView.swift`

## 実装の目的
まずは「普通のチャットアプリとして成立する最小機能」を作る。

## 画面構成
1. ヘッダー
- `Text("KadoZero")`

2. メッセージ一覧
- `ScrollViewReader`
- `ScrollView`
- `LazyVStack`
- `ForEach(messages)`

3. 入力エリア
- `TextField`
- 送信ボタン（`Button`）

## データ構造

```swift
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}
```

- `id`: 一意識別子（`ForEach` に必要）
- `text`: メッセージ本文
- `isUser`: 自分か相手かの判定

## 送信処理の流れ
`sendMessage()` の中で次を実行する。

1. 入力文字列の前後空白を削除
2. 空文字なら送信しない
3. 入力欄を空にする
4. 自分のメッセージを `messages` に追加
5. 0.4秒後に仮の相手返信を `messages` に追加

## 吹き出しUI
`MessageBubble` で見た目を分岐する。

- `isUser == true`: 右寄せ・青背景・白文字
- `isUser == false`: 左寄せ・グレー背景・通常文字色

## 自動スクロール

```swift
.onChange(of: messages.count) {
    guard let lastId = messages.last?.id else { return }
    withAnimation {
        proxy.scrollTo(lastId, anchor: .bottom)
    }
}
```

- メッセージ件数が増えたら最新メッセージ位置まで移動する

## 現在の制約
- サーバー通信なし
- メッセージ永続化なし（アプリ再起動で消える）
- 相手返信は固定ロジック（仮実装）

## 次にやること（将来）
1. API連携（`APIClient` を接続）
2. 送信前レビューUI（提案文採用/そのまま送信）
3. 保存機能（ローカル or サーバー）
