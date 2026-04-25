# API Spec

## Endpoints
- GET /health
- POST /v1/messages/analyze

## Analyze Request
```json
{
  "message_id": "msg_001",
  "conversation_id": "conv_001",
  "text": "お前、なんでまだやってないの？馬鹿じゃないの",
  "tone_preference": "gentle",
  "language": "ja",
  "recent_messages": []
}
