# Kadozero README素材

このファイルは、Kadozero に関するメモの蓄積用です。
後で GitHub の `README.md` 向けに再構成します。

## 1. 一言で何を作っているか

- 誰も傷つけない、世界一優しいチャットアプリ。

## 2. 背景と課題意識

- 近年は在宅勤務の増加により、組織内コミュニケーションでもチャットアプリの利用が主流になってきた。
- 一方で、文字情報だけのやり取りでは表情やジェスチャーが伝わらず、意図せず相手を傷つけたり、必要以上に悪い印象を与えてしまうことがある。
- そのため、言葉を発する前に一度立ち止まらせてくれる「ストッパー」のような役割を持つチャットアプリがあってもよいと考えた。

## 3. 誰のどんな課題を解決したいか

- テキスト中心のコミュニケーションを行う人が、悪意がなくても相手を傷つけてしまうリスクを減らしたい。
- 特に、社内チャットや日常的なメッセージのやり取りにおいて、送信前に表現を見直せる余地を作りたい。

## 4. コア機能

- メッセージ送信時に、強い口調や攻撃的に受け取られうる表現を自動で判別する。
- 例えば、「お前」「馬鹿」のような表現が含まれている場合、AI がより優しい言葉遣いへ言い換えを提案する。
- 単にブロックするのではなく、送信内容をよりよい表現に変換することで、コミュニケーションの質を下げずに衝突を減らすことを目指す。

## 5. 送信前体験の設計

- 送信前に AI の判定結果と提案内容をユーザーが確認できるようにする。
- AI が提案した言い換えをそのまま採用するか、元の文面のまま送るかをユーザーが選べる設計にする。
- 自動変換で勝手に送信されるのではなく、最終判断は必ずユーザーに残す。
- 送信前画面では、元の文、提案文、理由をセットで提示し、ユーザーが納得した上で送信できるようにする。

### 送信前画面の表示例

```text
このメッセージは強い表現を含む可能性があります

元の文:
「お前、なんでまだやってないの？馬鹿じゃないの」

提案文:
「まだ対応できていないようなので、状況を教えてもらえますか？」

理由:
・「お前」が強く相手を責める印象を与える可能性があります
・「馬鹿じゃないの」が攻撃的に受け取られる可能性があります

[そのまま送る]  [提案を採用して送る]
```

### 送信前画面で見せたい要素

- 上部に「強い表現を含む可能性があります」のような注意メッセージを表示する。
- 元の文と提案文を並べて見せ、何がどう変わるのかを分かりやすくする。
- なぜ変換対象になったかを短い自然文で説明する。
- 最後は「そのまま送る」と「提案を採用して送る」の二択にする。

### 送信フロー

- ユーザーがチャット画面でメッセージを入力する。
- ユーザーが送信ボタンを押す。
- アプリはメッセージをそのまま相手に送らず、先に AI チェック API へ送る。
- AI は、強い表現が含まれているか、攻撃的に受け取られる可能性があるか、より優しい言い換え候補を作れるかを判定する。
- 問題がない場合は、そのままメッセージを送信する。
- 強い表現が含まれる場合は、送信前確認画面を表示する。
- ユーザーは「そのまま送る」か「提案を採用して送る」かを選ぶ。
- 選択された文面が最終的に相手へ送信される。

### フロー設計の意図

- 毎回確認画面を出すのではなく、問題があると判断されたときだけ表示することで、通常のチャット体験を損なわないようにする。
- AI が勝手に書き換えて送信するのではなく、最終的な判断はユーザーに残す。
- 送信意図そのものを否定するのではなく、相手に伝わる表現を少しだけやわらかくすることを重視する。

## 6. iOS クライアント

- SwiftUI でチャット画面を実装する想定。
- ユーザーが送信ボタンを押したとき、即時送信せずにバックエンド API へメッセージを送る。
- API の返却結果に応じて、そのまま送信するか、送信前確認画面を表示するかを切り替える。
- 送信前確認画面では `元の文 / 提案文 / 理由` を表示し、ユーザーが最終選択できるようにする。

## 7. Python バックエンド

- FastAPI を用いて、iOS クライアントからの送信前チェック要求を受ける。
- まずは `送信前チェック` を中心に据えた API にする。
- 初版では、1回のリクエストで「判定」「分析」「言い換え」「理由生成」まで返す形を想定する。

### API 設計方針

- iOS 側の実装を簡単にするため、送信前に必要な情報はできるだけ1回の API 呼び出しで返す。
- 将来的な拡張性を意識して、`/v1/` を付けたバージョニングありの API にする。
- LLM を使う前提でも、クライアントが扱うレスポンス形式は固定し、構造化 JSON を返す。
- 多少コストがかかっても、初版は精度と説明可能性を優先する。

### 初版のエンドポイント案

- `GET /health`
  バックエンドの疎通確認用。
- `POST /v1/messages/analyze`
  送信前メッセージの分析と言い換え提案を行うメイン API。
- `POST /v1/messages/feedback`
  ユーザーが提案を採用したかどうかを記録する任意 API。将来的な改善用。

### `POST /v1/messages/analyze`

#### 役割

- 入力されたメッセージを解析し、強い表現があるかを判定する。
- 必要に応じて、より優しい言い換え候補を生成する。
- ユーザーに見せる理由文も同時に返す。

#### リクエスト例

```json
{
  "message_id": "msg_001",
  "conversation_id": "conv_001",
  "text": "お前、なんでまだやってないの？馬鹿じゃないの",
  "tone_preference": "gentle",
  "language": "ja",
  "recent_messages": [
    {
      "role": "other",
      "text": "この件、今日中に対応できますか？"
    },
    {
      "role": "user",
      "text": "今確認しています"
    }
  ]
}
```

#### リクエスト項目の意図

- `message_id`
  クライアント側の送信候補メッセージを識別するため。
- `conversation_id`
  会話単位でログや将来の分析に紐付けやすくするため。
- `text`
  判定対象となる本文。
- `tone_preference`
  今後、「やさしめ」「ビジネス寄り」などトーン調整に対応しやすくするため。
- `language`
  多言語対応や将来のモデル切り替えを意識した項目。
- `recent_messages`
  文脈を踏まえた判定を行うため。多少コストがかかっても、初版は直近数件を与えて精度を優先してよい。

#### レスポンス例

```json
{
  "message_id": "msg_001",
  "should_review": true,
  "severity": "high",
  "toxicity_score": 0.87,
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

#### レスポンス項目の意図

- `should_review`
  送信前確認画面を出すべきかどうかを iOS 側が即座に判断できるようにするため。
- `severity`
  `low / medium / high` のような段階で、UI の出し分けや将来の分析に使いやすくするため。
- `toxicity_score`
  内部判定の参考値。ユーザーにそのまま見せなくても、ログや改善に利用できる。
- `emotion`
  怒り、不満、苛立ちなどの傾向を把握するため。
- `detected_expressions`
  どの表現が検知対象だったかを明確にするため。
- `suggested_text`
  提案文。`should_review=false` のときは元文と同じにするか、`null` にしてもよい。
- `reasons`
  UI 上にそのまま表示できる短い理由文。
- `analysis_summary`
  一文で全体判断を伝えるため。画面上部の注意メッセージにも使いやすい。

#### 問題なしの場合のレスポンス例

```json
{
  "message_id": "msg_002",
  "should_review": false,
  "severity": "low",
  "toxicity_score": 0.08,
  "emotion": "neutral",
  "detected_expressions": [],
  "original_text": "この件、今日の15時ごろに確認します",
  "suggested_text": null,
  "reasons": [],
  "analysis_summary": "強い表現は検知されませんでした。"
}
```

### `POST /v1/messages/feedback`

#### 役割

- ユーザーが AI 提案を採用したかどうかを記録する。
- 将来的に、どのような提案が受け入れられやすいかを分析するための土台にする。

#### リクエスト例

```json
{
  "message_id": "msg_001",
  "user_action": "accepted_suggestion",
  "final_text": "まだ対応できていないようなので、状況を教えてもらえますか？"
}
```

#### なぜ feedback API を置くか

- 単に言い換えを返して終わりにせず、ユーザーが実際にどう選んだかまで見ると改善余地が分かるため。
- インターン向けにも、「判定して終わり」ではなく「運用して改善する視点がある」と説明しやすいため。
- 将来的に、過剰変換が多いケースや、採用されやすいトーンを分析しやすくするため。

## 8. AI / LLM / Agent 要素

- 1回の送信に対して、AI は主に4つの役割を担う想定にしている。
- `toxicity_check`
  メッセージ内に攻撃的、威圧的、断定的な表現が含まれていないかを判定する。
- `emotion_analysis`
  文章の背後にある感情傾向を推定し、怒りや苛立ちが強く出ていないかを確認する。
- `rewrite_message`
  伝えたい内容は残したまま、相手に受け入れられやすい柔らかい表現へ変換する。
- `generate_reason`
  検知した表現と、言い換え意図をユーザーに説明する。

### AI 処理フローのイメージ

- 入力文
- 攻撃性判定
- 感情分析
- 必要なら言い換え生成
- 理由生成
- アプリへ返却

### なぜこの分割にしたか

- 1つのブラックボックス的な AI 処理にせず、判定、分析、生成、説明を分けることで、処理の役割を説明しやすくするため。
- どこでどの判断が行われたかを切り分けることで、意図しない変換が起きたときに見直しや改善をしやすくするため。
- 単に「AI で変換した」ではなく、「何を見て、どう判断し、どう提案したか」をユーザーや面接相手に説明できるようにするため。
- 将来的に Function Calling や Tool Use、Agent 的な構成へ広げる場合にも、役割単位で拡張しやすくするため。
- 最初から複雑なフレームワークに依存するのではなく、まずはシンプルな責務分割で設計意図を明確にしたいから。

### メモ段階の補足

- 現時点では厳密な実装方式を固定するというより、README や面接で説明できる設計の骨格を先に固めることを優先する。
- LangGraph のような構成を入れるかどうかは後で判断してよく、まずは役割分割が自然に説明できることを重視する。

### LLM をどう使うか

- 初版では、1つの高性能 LLM を中心に使い、`判定` `言い換え` `理由生成` をまとめて返す構成が現実的。
- ただし、アプリ内部では役割を `toxicity_check` `emotion_analysis` `rewrite_message` `generate_reason` に分けて設計しておく。
- こうしておくことで、最初は1モデルで実装しつつ、将来的には小さいモデルやルールベースへ役割ごとに置き換えやすい。

### インターンを意識したおすすめ構成

#### まず見せるべき構成

- `ルールベース前処理`
  明らかな強語を辞書的に検知する。
- `高性能 LLM`
  文脈込みで `should_review`、感情傾向、提案文、理由文を構造化して返す。
- `フィードバック収集`
  提案採用率や誤検知を蓄積する。

#### なぜこの構成にするか

- 初版として実装が現実的で、短期間でも完成度を出しやすい。
- 「単に LLM を呼んだ」ではなく、「ルール、判定、生成、改善」の流れで説明できる。
- GMO 向けには、Python バックエンド、構造化出力、Function Calling / Tool Use への拡張性を話しやすい。
- LINEヤフー向けには、最終的に重要なのは UX であり、モデル選定も UX を支える設計として説明しやすい。

### モデル選定の考え方

- 送信前の安全判定は、雑に安いモデルへ寄せるより、初版は精度重視でよい。
- 特に Kadozero は「誤変換しないこと」や「理由を自然に説明できること」が重要なので、まずは高性能モデルを使う方が筋がよい。
- コスト最適化は、ログが溜まり、どこが本当に重いか分かってからで十分。

### 実装パターン案

#### パターンA: 初版向け

- 1回の API 呼び出しで、高性能 LLM に構造化 JSON を返させる。
- 返す項目は `should_review` `severity` `emotion` `suggested_text` `reasons` などに固定する。
- 最も実装が速く、README や面接でも説明しやすい。

#### パターンB: 改善版向け

- 前段で軽いルールベース判定を行う。
- 強い語がない場合でも、必要に応じて LLM へ送る。
- 強い語がある場合は必ず LLM を通し、文脈込みで確認画面が必要かを判断する。
- 多少複雑になるが、再現性と精度のバランスを取りやすい。

#### パターンC: 発展版向け

- 判定は軽量分類器または小型モデル、言い換え生成は高性能モデルに分離する。
- コストや応答速度を最適化しやすいが、初版としてはやや作り込みすぎ。

### 今のおすすめ結論

- 今月中に見せる成果物としては、`パターンA + 最低限のルールベース` が最も良い。
- つまり、表面的にはシンプルな API にしつつ、内部の思想としては役割分割と改善余地を持たせる。
- これが一番、実装、説明、インターン訴求のバランスがよい。

### Gemini 無料枠を使う方針

- 初版では、外部GPUサーバーやローカルLLMの常設運用は行わず、Gemini の無料枠を使って実装する。
- Kadozero の中心は短文メッセージの送信前チェックであり、無料枠でも十分に試作しやすい。
- この段階では「ローカルLLMを今すぐ動かすこと」よりも、「ローカルLLMにも置き換え可能な設計」を持っていることの方が重要。

### 初版で使うモデル案

- 第一候補: `Gemini 2.5 Flash`
- 必要に応じた節約候補: `Gemini 2.5 Flash-Lite`

### なぜ Gemini 2.5 Flash を第一候補にするか

- Kadozero では、単なる分類だけでなく、自然な言い換え文と理由文の生成品質が重要だから。
- 送信前 UX においては、少し高性能なモデルを使った方が「変な言い換え」が減りやすい。
- 無料枠でも十分に検証できる範囲があり、初版としてはコストをかけずに進めやすい。

### 使い分けの考え方

- まずは `Gemini 2.5 Flash` 1本で実装する。
- 必要になったら、軽い判定を `Flash-Lite`、言い換え生成を `Flash` に分ける。
- ただし初版で複雑化しすぎないために、最初は1モデル構成を優先する。

### Gemini 無料枠を使う上での注意

- 無料枠では、入力内容が Google のプロダクト改善に利用される前提がある。
- そのため、初版の Kadozero は実データや機微情報を扱う本番用途ではなく、プロトタイプとして位置づける。
- README や説明でも、「個人情報や機微情報を含まない検証用データを前提に開発する」と明記した方が安全。

### Gemini 前提の API 実装方針

- FastAPI 側で `POST /v1/messages/analyze` を受ける。
- バックエンドは Gemini API を呼び出し、構造化 JSON を生成させる。
- iOS 側には、モデル固有の情報を隠し、常に同じ JSON 形式で返す。
- これにより、将来的に Gemini から OpenAI やローカルLLMへ差し替えても、クライアント側の変更を最小限にできる。

### Gemini に返させたい構造

```json
{
  "should_review": true,
  "severity": "high",
  "emotion": "anger",
  "detected_expressions": ["お前", "馬鹿じゃないの"],
  "suggested_text": "まだ対応できていないようなので、状況を教えてもらえますか？",
  "reasons": [
    "「お前」が強く相手を責める印象を与える可能性があります",
    "「馬鹿じゃないの」が攻撃的に受け取られる可能性があります"
  ],
  "analysis_summary": "強い否定と責める口調が含まれているため、送信前確認を推奨します。"
}
```

### 初版の実装イメージ

- 1. iOS からメッセージ本文を FastAPI に送る。
- 2. FastAPI 側で簡易ルールベース判定を行う。
- 3. 必要に応じて Gemini へプロンプトを送り、構造化レスポンスを生成させる。
- 4. FastAPI が Kadozero 用のレスポンス形式に整えて返す。
- 5. iOS 側で `should_review` を見て、そのまま送信するか確認画面を出すか分岐する。

### なぜこの構成がよいか

- iOS 側に LLM の詳細を持ち込まず、責務を明確に分離できる。
- モデルを差し替えても API 仕様を維持しやすい。
- 「Gemini を使った」だけでなく、「プロダクト都合に合わせてバックエンドで吸収した」と説明できる。

### Gemini 用 system prompt 案

```text
You are the message safety and tone assistant for Kadozero, a chat application that helps users avoid unintentionally hurting others before sending a message.

Your job is to analyze a user's draft message and return a structured result for the app UI.

Goals:
1. Detect whether the message contains expressions that may sound aggressive, insulting, overly harsh, or emotionally harmful.
2. Preserve the user's original intent as much as possible.
3. If needed, rewrite the message into a gentler and more socially acceptable expression.
4. Explain briefly and clearly why the message should be reviewed.
5. Do not over-correct neutral or acceptable business communication.

Output policy:
- Always return valid JSON only.
- Follow the provided schema exactly.
- Do not add any extra keys.
- Do not include markdown or commentary outside the JSON.

Decision policy:
- Set should_review to true when the message is likely to hurt, pressure, insult, or strongly blame the other person.
- Set should_review to false when the message is acceptable as-is, even if it contains mild disagreement or directness.
- Avoid excessive rewriting. Keep the meaning, request, and urgency whenever possible.
- If the message is already acceptable, suggested_text should be null or nearly identical to the original.
- Reasons must be short, natural, and understandable to end users.
- Do not make the rewritten message unnaturally formal unless necessary.
- Prefer Japanese output when the input is Japanese.

Severity policy:
- low: slightly strong or blunt, but not clearly harmful
- medium: contains noticeable blame, pressure, or emotionally harsh wording
- high: contains insulting, demeaning, or strongly aggressive wording

Emotion policy:
- Return one of: neutral, frustration, anger, sadness, anxiety
- Choose the closest dominant emotion expressed in the message

Detected expressions policy:
- Include short spans or phrases from the original text that triggered review
- If there are no clear problematic expressions, return an empty list

Important constraints:
- Do not moralize.
- Do not lecture the user.
- Do not change the core request unless the original wording is clearly harmful.
- The final decision belongs to the user, so your role is to support review, not to censor.
```

### few-shot の役割

- system prompt だけでは曖昧になりやすい「どの程度で review にするか」「どのくらい柔らかく言い換えるか」を、具体例で固定するために few-shot を入れる。
- few-shot は学習データではなく、プロンプト内でモデルに見せる見本として使う。
- 初版では、`強い表現` `少し強い表現` `問題ない表現` の3例を置くのがよい。

### Gemini 用 few-shot 例

#### Example 1: 明確に review が必要な例

Input:

```json
{
  "text": "お前、なんでまだやってないの？馬鹿じゃないの",
  "recent_messages": [],
  "tone_preference": "gentle",
  "language": "ja"
}
```

Output:

```json
{
  "should_review": true,
  "severity": "high",
  "emotion": "anger",
  "detected_expressions": ["お前", "馬鹿じゃないの"],
  "suggested_text": "まだ対応できていないようなので、状況を教えてもらえますか？",
  "reasons": [
    "「お前」が強く相手を責める印象を与える可能性があります",
    "「馬鹿じゃないの」が攻撃的に受け取られる可能性があります"
  ],
  "analysis_summary": "強い否定と責める口調が含まれているため、送信前確認を推奨します。"
}
```

#### Example 2: 少し強いが、やわらげれば十分な例

Input:

```json
{
  "text": "それ違うと思う。ちゃんと確認して",
  "recent_messages": [],
  "tone_preference": "gentle",
  "language": "ja"
}
```

Output:

```json
{
  "should_review": true,
  "severity": "medium",
  "emotion": "frustration",
  "detected_expressions": ["それ違うと思う", "ちゃんと確認して"],
  "suggested_text": "その点は認識が異なるかもしれないので、もう一度確認してもらえると助かります。",
  "reasons": [
    "否定が直接的に伝わる可能性があります",
    "指示の表現がやや強く受け取られる可能性があります"
  ],
  "analysis_summary": "やや強い否定と指示が含まれているため、やわらかい表現への見直しを推奨します。"
}
```

#### Example 3: review 不要な例

Input:

```json
{
  "text": "この件、今日の15時ごろに確認します",
  "recent_messages": [],
  "tone_preference": "gentle",
  "language": "ja"
}
```

Output:

```json
{
  "should_review": false,
  "severity": "low",
  "emotion": "neutral",
  "detected_expressions": [],
  "suggested_text": null,
  "reasons": [],
  "analysis_summary": "強い表現は検知されませんでした。"
}
```

### few-shot を入れる意図

- Kadozero は単なる毒性検知ではなく、「不自然すぎない優しい言い換え」が重要だから。
- 例を見せることで、モデルに Kadozero のトーンや review 基準を具体的に伝えやすくなる。
- few-shot を通じて、「必要以上に丁寧にしすぎない」「業務上自然な言い換えにする」という方針を安定させやすい。

## 14. AIエージェントに渡す実装タスク案

### 実装の基本方針

- 私は概念設計と仕様決定を担当し、実装は AI エージェントに依頼する前提で進める。
- そのため、タスクは「1回で完成させる大きな依頼」ではなく、「責務が明確でレビューしやすい単位」に分割する。
- 初版では、iOS、バックエンド、Docker/README を分けて依頼するのがよい。

### タスク1: SwiftUI でチャット画面と送信前確認画面を作る

#### 依頼文案

```text
Kadozero の iOS クライアント初版を SwiftUI で実装してください。

目的:
- 1対1チャット画面を作る
- メッセージ送信時にバックエンド API を呼ぶ
- review が必要な場合は送信前確認画面を表示する

必要な画面:
- チャット一覧画面
- チャット画面
- 送信前確認モーダルまたは確認画面

送信前確認画面で表示する項目:
- 注意メッセージ
- 元の文
- 提案文
- 理由一覧
- 「そのまま送る」
- 「提案を採用して送る」

API 連携仕様:
- `POST /v1/messages/analyze` を呼ぶ
- `should_review` が false の場合はそのまま送信
- `should_review` が true の場合は確認画面を表示

今回の実装範囲:
- UI と状態管理
- API クライアント
- ダミーデータまたはモックでも確認できる構成

完了条件:
- チャット画面から送信操作ができる
- API レスポンスに応じて確認画面が出し分けられる
- 「そのまま送る」「提案を採用して送る」で最終送信文が分岐する
```

#### このタスクを分ける理由

- LINEヤフー向けに見せたい iOS/UX 部分を独立して作り込みやすいため。
- バックエンド未完成でも、モックで先に UI 検証を進められるため。

### タスク2: FastAPI + Gemini で送信前分析 API を実装する

#### 依頼文案

```text
Kadozero のバックエンド初版を Python + FastAPI で実装してください。

目的:
- 送信前メッセージを受け取り、Gemini API を使って分析する
- Kadozero 用の構造化 JSON を返す

実装対象:
- `GET /health`
- `POST /v1/messages/analyze`
- 必要なら `POST /v1/messages/feedback`

`/v1/messages/analyze` の役割:
- 入力文を受け取る
- 簡易ルールベースで強い表現を前処理する
- Gemini 2.5 Flash を呼び出す
- system prompt と few-shot を使って JSON を生成させる
- Kadozero のレスポンス形式に整形して返す

リクエスト例:
{
  "message_id": "msg_001",
  "conversation_id": "conv_001",
  "text": "お前、なんでまだやってないの？馬鹿じゃないの",
  "tone_preference": "gentle",
  "language": "ja",
  "recent_messages": []
}

レスポンスで返す項目:
- should_review
- severity
- emotion
- detected_expressions
- original_text
- suggested_text
- reasons
- analysis_summary

実装要件:
- Pydantic で request/response schema を定義する
- Gemini の返答は構造化 JSON として扱う
- パース失敗時のフォールバックを入れる
- 環境変数で API キーを読む
- ログを最低限残す

完了条件:
- ローカルで FastAPI が起動する
- `/health` が返る
- `/v1/messages/analyze` に対して JSON レスポンスが返る
- 強い表現あり/なしの両ケースで動作確認できる
```

#### このタスクを分ける理由

- GMO 向けに見せたい Python / LLM / API 設計部分の中核だから。
- iOS と独立して検証でき、仕様の変更にも対応しやすいため。

### タスク3: Docker 化と README の最小整備を行う

#### 依頼文案

```text
Kadozero バックエンドを Docker で起動できるようにし、README の最小構成を整備してください。

目的:
- ローカル環境差分を減らす
- 実行手順を第三者に説明できるようにする

実装対象:
- Dockerfile
- 必要なら docker-compose.yml または compose.yaml
- `.env.example`
- README の起動手順セクション

README に最低限入れる内容:
- アプリ概要
- 技術スタック
- バックエンドの起動方法
- 環境変数の設定方法
- API エンドポイント概要

完了条件:
- Docker で FastAPI が起動する
- README を見れば第三者が起動できる
- `.env.example` に必要な環境変数が整理されている
```

#### このタスクを分ける理由

- GMO 向けでは Docker による再現性の説明が重要だから。
- アプリ本体の実装と分けることで、最終盤に整理しやすくなるため。

### タスク4: Agent/Tool Use を説明できる形に整理する

#### 依頼文案

```text
Kadozero の Python バックエンドを、将来的に Agent / Tool Use 構成へ拡張できるよう整理してください。

目的:
- GMO 向けに「チャットボット」ではなく「AI Agent 的に設計した」と説明できるようにする

実装対象:
- `toxicity_check`
- `emotion_analysis`
- `rewrite_message`
- `generate_reason`

要件:
- まずは内部関数分割でよい
- 1回の API 呼び出しで最終レスポンスを返せる形は維持する
- 将来的に Function Calling や Tool Use に移行しやすい責務分割にする

完了条件:
- 各役割が関数またはモジュールとして分かれている
- README かコメントで責務が説明されている
- 単なる1本の巨大処理になっていない
```

#### このタスクを分ける理由

- 今すぐ LangGraph を入れなくても、Agent 的な説明ができる構造を作れるため。
- 「設計上そうしている」こと自体が GMO 向けの訴求になるため。

### タスクを出す順番

- 1. FastAPI + Gemini API
- 2. SwiftUI UI 実装
- 3. Docker / README
- 4. Agent 的な責務分割

### なぜこの順番にするか

- API 仕様が先に固まると、iOS 側が迷わず実装できる。
- SwiftUI はモックでも進められるが、最終的には API 契約が必要だから。
- Docker と README は中核機能が動いてからまとめた方が無駄が少ない。
- Agent 化は初版の完成を壊さない範囲で、後から整理しても十分間に合う。

## 9. 技術スタック

- iOS クライアント: Swift / SwiftUI
- バックエンド: Python / FastAPI
- 実行環境: Docker
- AI 処理: LLM API を利用した構造化出力
- バージョン管理 / 公開: Git / GitHub

### 技術選定の意図

- SwiftUI は LINEヤフー向けにも説明しやすく、iOS クライアントの完成度を見せやすい。
- Python + FastAPI は実装速度と説明のしやすさのバランスがよい。
- Docker を入れることで、GMO 向けに再現性や実行環境の整理をアピールしやすい。
- GitHub を使うことで、成果物を第三者に見せられる形にし、設計・実装・README の整備まで含めてアピールしやすい。
- AI 部分は初版では外部 LLM API を使い、モデル開発よりもプロダクト設計と UX に集中する。

## 10. 工夫した点

- 

## 11. 難しさと対策

- 難しさ:
- 攻撃的かどうかの閾値が AI 依存になりやすい。
- 文脈によっては、意図しない変換や過剰な変換が起こる可能性がある。
- 対策:
- AI の変換結果を送信前に必ず確認できるようにする。
- 自動で書き換えて送信するのではなく、ユーザーが提案を採用するかどうかを選べる形にすることで、過剰変換のリスクを下げる。

### 判断ポリシー案

- 基本方針は「送信を禁止する」のではなく、「送信前に一度見直す機会を作る」ことに置く。
- 強い言葉が含まれていても、必ずしも送信不可にはせず、まずは確認画面を出す設計にする。
- ユーザーの意図を消すのではなく、相手への伝わり方をやわらかく整えることを優先する。

### 送信前確認を出す条件

- 侮辱的な語句や強い二人称が含まれている場合。
- 相手を責めるような断定的表現が含まれている場合。
- 怒りや苛立ちが強く出ていると推定された場合。
- 文脈を含めて見たときに、攻撃的に受け取られる可能性が高い場合。

### そのまま送信してよい条件

- 業務連絡として自然で、攻撃性が低い場合。
- 否定や指摘を含んでいても、表現が丁寧で相手への配慮がある場合。
- AI が強い表現を検知しなかった場合。

### 初版でのおすすめ実装方針

- ルールベースと LLM 判定を併用する。
- まず、`お前` `馬鹿` など明らかに強い語を辞書的に拾う。
- その上で、LLM に文脈込みで「送信前確認が必要か」を判定させる。
- どちらか一方だけに依存せず、分かりやすさと柔軟性を両立させる。

### なぜこの方針がおすすめか

- すべてを LLM 任せにすると、判定理由や再現性が弱くなりやすい。
- 逆にルールベースだけでは、文脈を見た柔軟な判断が難しい。
- 初版では、明らかな強い語はルールで補足し、最終判断は LLM に寄せる形がバランスがよい。
- 面接でも、「辞書ベースの検知」と「文脈込みの意味判断」を組み合わせていると説明しやすい。

### 初版のしきい値の考え方

- `should_review` は、少しでも怪しい場合に広めに `true` を返す保守的な設計でよい。
- 初版では見逃しよりも「確認を促す」ことを重視する。
- ただし、毎回確認画面が出ると UX が悪化するため、明らかに問題ない文はそのまま通す。

### 初版で避けたいこと

- 送信そのものを強制的にブロックすること。
- AI が自動で書き換えて、そのまま送信してしまうこと。
- 微妙なニュアンスまで過剰に修正して、使いにくいアプリになること。

### ルールベースと学習の考え方

- ルールベースは、モデルが自動で学習するというより、人が条件や辞書を更新して育てていくものとして考える。
- 例えば `お前` `馬鹿` のような明らかに強い表現は、辞書やルールで検知しやすい。
- 一方で、文脈依存の微妙な強さや皮肉、圧のある言い回しはルールだけでは拾いきれない。
- そのため、初版ではルールベース単体に寄せすぎず、LLM と組み合わせて使う方が現実的。

### 進化ロードマップ

#### 初版

- ルールベース + LLM の併用にする。
- 明らかな強い表現は辞書や単純なルールで検知する。
- 最終的な `should_review` の判断や言い換え生成は LLM に担わせる。
- まずは実装速度、説明可能性、UX の成立を優先する。

#### 改善版

- `feedback` API で、ユーザーが提案を採用したか却下したかを蓄積する。
- どの表現で誤検知が多いか、どの提案が受け入れられやすいかを分析する。
- その結果をもとに、ルールや辞書、しきい値を改善する。
- つまり、ルールベースを運用で育てていく段階と位置づける。

#### 発展版

- 蓄積したログや評価用ケースを使って、軽量な分類器やポリシーモデルを導入する余地がある。
- 最初はルールで付けた仮ラベルや、ユーザーフィードバックをもとに学習データを作ることも考えられる。
- これにより、毎回すべてを LLM に依存せず、判定部分のコストや一貫性を改善できる可能性がある。
- 将来的には、ルール、軽量分類器、LLM を役割分担させる構成も考えられる。

### なぜこの段階設計にするか

- 最初から学習器まで作ろうとすると、データ収集、ラベリング、評価設計まで必要になり、初版としては重すぎるため。
- まずはプロダクトとして価値のある UX を成立させ、その上でログを蓄積した方が改善の方向性を見極めやすい。
- インターンでも、「初版は説明可能性と実装速度を優先し、運用データが溜まったら学習ベースへ発展させる」と説明できる。

## 12. 今後の拡張

- 

## 13. 応募企業ごとの見せ方メモ

### LINEヤフー

- 

### GMO

- GMO のデータ＆AIエンジニアコースを意識し、Kadozero は `Python + Docker + AI Agent` の構成で説明できるようにしたい。
- 特に、単なるチャットボットではなく、`判定` `言い換え` `理由生成` `フィードバック収集` のように役割が分かれた処理系として見せたい。
- Tool Use / Function Calling に拡張しやすい構成にしておくことで、「外部APIやデータベースを利用してタスクを実行する仕組み」への理解があることを示せる。
- データ収集、データ整形、精度向上、サニタイジング、ガードレール実装まで視野に入れている点を強調したい。
- 初版では外部 LLM API を使ってもよいが、将来的にはローカルLLMに置き換え可能な構成として設計している、と説明できるようにしたい。
- `feedback` による改善ループを入れることで、「作って終わり」ではなく、精度向上まで含めて考えていることを示せる。
- ガードレールの観点では、過剰変換や意図しない変換を防ぐために、送信前確認とユーザー選択を必ず挟む設計が重要。

### ソフトバンク

- 

### PKSHA

- 
