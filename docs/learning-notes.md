# KadoZero 開発メモ

## ステップ1：データモデルの定義

### データモデルとは？
アプリとサーバーの間でやり取りするデータの「型」を決めたもの。
仕様書にあったJSON（リクエストとレスポンス）を、Swiftの構造体（`struct`）として定義する。

### 作成ファイル
- `Models.swift`（`KadoZero`フォルダ内に新規作成）

### 新規ファイルの作り方（Xcode）
1. 左のファイルツリーで `KadoZero`フォルダを右クリック
2. 「New File...」を選択
3. 「Swift File」を選んで「Next」
4. ファイル名を `Models` にして「Create」

### コードの中身

```swift
import Foundation

// MARK: - リクエスト（アプリ → サーバーに送るデータ）

struct AnalyzeRequest: Codable {
    let messageId: String
    let conversationId: String
    let text: String
    let tonePreference: String
    let language: String
    let recentMessages: [String]

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case text
        case tonePreference = "tone_preference"
        case language
        case recentMessages = "recent_messages"
    }
}

// MARK: - レスポンス（サーバー → アプリに返ってくるデータ）

struct AnalyzeResponse: Codable {
    let messageId: String
    let shouldReview: Bool
    let severity: String
    let emotion: String
    let detectedExpressions: [String]
    let originalText: String
    let suggestedText: String
    let reasons: [String]
    let analysisSummary: String

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case shouldReview = "should_review"
        case severity
        case emotion
        case detectedExpressions = "detected_expressions"
        case originalText = "original_text"
        case suggestedText = "suggested_text"
        case reasons
        case analysisSummary = "analysis_summary"
    }
}
```

### 用語まとめ

| 要素 | 意味 |
|------|------|
| `struct` | データのまとまりを定義する箱 |
| `Codable` | JSONとSwiftの型を自動で変換できるようにする仕組み |
| `let` | 変更不可の値（受け取ったら変えない） |
| `CodingKeys` | JSONのキー名（`message_id`）とSwiftのプロパティ名（`messageId`）を対応させる辞書 |
| `// MARK: -` | コードをセクション分けするためのXcode用コメント。ジャンプバーに表示される |

### なぜ CodingKeys が必要？
- JSONでは `snake_case`（例: `message_id`）が一般的
- Swiftでは `camelCase`（例: `messageId`）が一般的
- この2つを対応づけるのが `CodingKeys` の役割
- 例: `"message_id": "msg_001"` → Swift側では `request.messageId` でアクセス可能

---

## ステップ2：APIクライアントの作成

### APIクライアントとは？
アプリからサーバーにデータを送ったり、サーバーからの返事を受け取ったりする「通信係」。
ステップ1で定義した `AnalyzeRequest` を送り、`AnalyzeResponse` を受け取る処理を書く。

### 作成ファイル
- `APIClient.swift`（`KadoZero`フォルダ内に新規作成）

### コードの中身

```swift
import Foundation

class APIClient {

    // サーバーのURL（後で本番用に変更する）
    private let baseURL = "http://localhost:8000"

    // メッセージを分析するリクエストを送る
    func analyzeMessage(text: String) async throws -> AnalyzeResponse {
        // 1. URLを組み立てる
        let url = URL(string: "\(baseURL)/v1/messages/analyze")!

        // 2. リクエストを作る
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 3. 送るデータを作る
        let body = AnalyzeRequest(
            messageId: UUID().uuidString,
            conversationId: "conv_001",
            text: text,
            tonePreference: "gentle",
            language: "ja",
            recentMessages: []
        )

        // 4. SwiftのstructをJSONに変換する
        request.httpBody = try JSONEncoder().encode(body)

        // 5. サーバーに送って、返事を待つ
        let (data, _) = try await URLSession.shared.data(for: request)

        // 6. 返ってきたJSONをSwiftのstructに変換する
        let response = try JSONDecoder().decode(AnalyzeResponse.self, from: data)

        return response
    }
}
```

### 処理の流れ

```
アプリ                          サーバー
  |                               |
  |  1. AnalyzeRequest を作る      |
  |  2. JSONに変換                 |
  |  3. POST で送信 ------------->  |
  |                               |  4. AIが分析
  |  5. JSONが返ってくる <---------  |
  |  6. AnalyzeResponse に変換     |
  |  7. 画面に表示（後のステップ）    |
```

### 用語まとめ

| 要素 | 意味 |
|------|------|
| `class` | `struct` と似ているが、参照型で共有して使える。通信係は1つを使い回すので `class` が適切 |
| `private` | このクラスの中だけで使える（外から直接触れない） |
| `async` | 「この処理は時間がかかるよ」という印。サーバーの返事を待つ間、アプリが固まらない |
| `throws` | 「この処理は失敗するかもしれないよ」という印。通信エラーなどに備える |
| `URLRequest` | 「どこに、どんな方法で、何を送るか」をまとめたもの |
| `URLSession.shared.data(for:)` | 実際にサーバーと通信する部分 |
| `JSONEncoder().encode()` | Swift の struct → JSON に変換 |
| `JSONDecoder().decode()` | JSON → Swift の struct に変換 |

---

## ステップ3：チャット画面のUI

### 何を作る？
LINEやiMessageのような、メッセージが縦に並んで下に入力欄がある画面。

### 変更ファイル
- `ContentView.swift`（既存ファイルを書き換え）

### 画面の構造

```
┌──────────────────────┐
│      KadoZero        │  ← ヘッダー
├──────────────────────┤
│                      │
│  メッセージ1          │  ← ScrollView + LazyVStack
│         メッセージ2   │    メッセージが増えるとスクロール可
│                      │
├──────────────────────┤
│ [入力欄      ] [送信] │  ← HStack（横並び）
└──────────────────────┘
```

### コードの中身

```swift
import SwiftUI

// MARK: - チャット画面のメインView

struct ContentView: View {
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []

    var body: some View {
        VStack(spacing: 0) {
            // --- ヘッダー ---
            Text("KadoZero")
                .font(.headline)
                .padding()

            Divider()

            // --- メッセージ一覧 ---
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }

            Divider()

            // --- 入力エリア ---
            HStack {
                TextField("メッセージを入力", text: $inputText)
                    .textFieldStyle(.roundedBorder)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.isEmpty)
            }
            .padding()
        }
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        let newMessage = ChatMessage(text: text, isUser: true)
        messages.append(newMessage)
    }
}

// MARK: - メッセージのデータ型

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool   // true = 自分, false = 相手
}

// MARK: - 吹き出しの見た目

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            Text(message.text)
                .padding(12)
                .background(message.isUser ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(message.isUser ? .white : .primary)
                .cornerRadius(16)

            if !message.isUser { Spacer() }
        }
    }
}
```

### 用語まとめ

| 要素 | 意味 |
|------|------|
| `@State` | 画面の状態を保持する変数。値が変わると画面が自動で更新される |
| `$inputText` | `@State` 変数を双方向でつなぐ。テキスト入力と変数が連動する |
| `ScrollView` | 中身が多い時にスクロールできる領域 |
| `LazyVStack` | 縦に要素を並べる。`Lazy` は見えている分だけ描画する（効率的） |
| `ForEach` | 配列の要素を1つずつ繰り返して表示する |
| `Identifiable` | 各要素に一意のIDがあることを示す。`ForEach` で使うのに必要 |
| `Spacer()` | 空白を埋める。自分のメッセージを右寄せ、相手を左寄せにするのに使う |
| `HStack` | 要素を横に並べる |
| `VStack` | 要素を縦に並べる |
| `.disabled()` | 条件が `true` の時、ボタンを押せなくする |

---

## Git の初期設定

### Git とは？
コードの変更履歴を記録・管理するツール。「いつ・誰が・何を変えたか」が全て残る。
もし壊してしまっても過去の状態に戻せるので、安心してコードを変更できる。

### GitHub とは？
Git の履歴をインターネット上に保存・共有できるサービス。
ローカル（自分のPC）のコードをGitHubにアップロード（プッシュ）することで、バックアップにもなる。

### 作成ファイル
- `.gitignore` — gitに含めたくないファイルのリスト
- `LICENSE` — ソフトウェアの利用条件（MIT License）

---

### 手順1：GitHubにリポジトリを作成

1. ブラウザで github.com を開いてログイン
2. 右上の「+」→「New repository」をクリック
3. 設定：
   - Repository name: `Kadozero_ios`
   - 「Add a README file」→ チェックしない
   - 「Add .gitignore」→ チェックしない
   - 「Choose a license」→ 選択しない
4. 「Create repository」をクリック

**注意:** GitHub側でファイルを追加すると、ローカルとの整合が面倒になるため、すべてチェックなしで作成する。

### 手順2：ターミナルで実行するコマンド

```bash
# 1. プロジェクトフォルダに移動
cd ~/Dev/Kadozero_ios

# 2. gitを初期化
git init

# 3. .gitignoreを作成
echo '*.xcuserstate
xcuserdata/
build/
DerivedData/
.DS_Store' > .gitignore

# 4. LICENSEファイルを作成（MIT License）
cat << 'EOF' > LICENSE
MIT License

Copyright (c) 2026 Yuto Nishioka
...（省略）
EOF

# 5. 全ファイルをステージング
git add -A

# 6. 最初のコミットを作成
git commit -m "Initial commit: プロジェクト初期構成"

# 7. リモートリポジトリを登録
git remote add origin https://github.com/ユーザー名/Kadozero_ios.git

# 8. プッシュ
git push -u origin main
```

### コマンド解説

| コマンド | 意味 | なぜ使う？ |
|---------|------|-----------|
| `cd ~/Dev/Kadozero_ios` | プロジェクトフォルダに移動 | gitコマンドは対象フォルダ内で実行する必要がある |
| `git init` | このフォルダをgitで管理し始める | 最初に1回だけ実行。`.git` という隠しフォルダが作られる |
| `echo '...' > .gitignore` | `.gitignore` ファイルを作成 | 不要なファイルをgitの管理対象から除外するため |
| `cat << 'EOF' > LICENSE` | `LICENSE` ファイルを作成 | 利用条件を明記するため。OSSでは必須級 |
| `git add -A` | 全ファイルをステージング | 「次のコミットにこれらを含めます」と宣言する操作 |
| `git commit -m "..."` | 変更をまとめて記録する | コードのスナップショットを作る。`-m` の後がコミットメッセージ |
| `git remote add origin URL` | プッシュ先のGitHub URLを登録 | 「アップロード先はここ」とgitに教える |
| `git push -u origin main` | GitHubにアップロード | `-u` は「今後はこのブランチをデフォルトにする」という意味 |

### .gitignore に書いた内容の意味

| パターン | 除外するもの | なぜ除外？ |
|---------|------------|-----------|
| `*.xcuserstate` | Xcodeのウィンドウ位置等の個人設定 | 開発者ごとに異なり、共有不要 |
| `xcuserdata/` | Xcodeのユーザー固有データフォルダ | 同上 |
| `build/` | ビルド成果物 | コードから再生成できるので不要 |
| `DerivedData/` | Xcodeのキャッシュ | 同上 |
| `.DS_Store` | macOSが自動生成するフォルダ情報 | OS固有のファイルで共有不要 |

### LICENSE（MIT License）とは？
「このソフトウェアは自由に使っていいけど、著作権表示は残してね」という緩いライセンス。
OSSプロジェクトで最も広く使われている。

### Git の基本的な流れ（今後の開発でも繰り返す）

```
コードを書く → git add -A → git commit -m "変更内容" → git push
```

1. コードを変更する
2. `git add -A` で変更をステージング
3. `git commit -m "何を変更したかのメッセージ"` で記録
4. `git push` でGitHubにアップロード
