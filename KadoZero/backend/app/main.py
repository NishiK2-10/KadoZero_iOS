import json
import os
import re
import ssl
import uuid
from datetime import datetime
from urllib import error, request

import certifi
import jwt
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel
from sqlalchemy.exc import IntegrityError
from sqlalchemy import and_, select
from sqlalchemy.orm import Session

from .db import Base, SessionLocal, engine
from .db_models import Conversation, ConversationMember, Friendship, Message, RefreshToken, User
from .security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    hash_password,
    hash_refresh_token,
    utc_now,
    verify_password,
)

load_dotenv()

app = FastAPI(title="KadoZero API", version="0.2.0")

GEMINI_MODEL = "gemini-2.5-flash"
ADMONITION_PHRASES = [
    "より丁寧な表現をご検討ください",
    "言ってはいけません",
    "不適切です",
    "控えてください",
    "やめましょう",
]


class AnalyzeRequest(BaseModel):
    message_id: str
    conversation_id: str
    text: str
    tone_preference: str
    language: str
    recent_messages: list[str]


class AnalyzeResponse(BaseModel):
    message_id: str
    should_review: bool
    severity: str
    emotion: str
    detected_expressions: list[str]
    original_text: str
    suggested_text: str
    reasons: list[str]
    analysis_summary: str


class SignupRequest(BaseModel):
    email: str
    password: str
    display_name: str
    handle: str
    device_id: str = "ios-device"


class LoginRequest(BaseModel):
    email: str
    password: str
    device_id: str


class RefreshRequest(BaseModel):
    refresh_token: str
    device_id: str


class LogoutRequest(BaseModel):
    refresh_token: str | None = None


class MeResponse(BaseModel):
    id: str
    handle: str
    display_name: str
    email: str


class AuthResponse(BaseModel):
    user: MeResponse
    access_token: str
    refresh_token: str

class FriendSummaryResponse(BaseModel):
    id: str
    handle: str
    display_name: str


class FriendAddRequest(BaseModel):
    user_id: str


class ConversationCreateRequest(BaseModel):
    kind: str
    member_ids: list[str]
    title: str | None = None


class ConversationSummaryResponse(BaseModel):
    id: str
    kind: str
    title: str | None
    last_message: str | None
    unread_count: int


class MessageCreateRequest(BaseModel):
    client_message_id: str
    body: str
    original_body: str | None = None
    kind: str = "text"


class MessageResponse(BaseModel):
    id: str
    conversation_id: str
    sender_id: str
    body: str
    original_body: str | None = None
    kind: str
    created_at: datetime


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@app.on_event("startup")
def startup() -> None:
    Base.metadata.create_all(bind=engine)
    if not os.getenv("JWT_SECRET"):
        raise RuntimeError("JWT_SECRET is required in environment")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _normalize_handle(handle: str) -> str:
    trimmed = handle.strip()
    if not trimmed.startswith("@"):
        trimmed = f"@{trimmed}"
    return trimmed


def _validate_password_strength(password: str) -> None:
    if len(password) < 10:
        raise HTTPException(status_code=400, detail="password must be at least 10 chars")
    categories = 0
    categories += bool(re.search(r"[a-z]", password))
    categories += bool(re.search(r"[A-Z]", password))
    categories += bool(re.search(r"\d", password))
    categories += bool(re.search(r"[^A-Za-z0-9]", password))
    if categories < 2:
        raise HTTPException(status_code=400, detail="password must include at least 2 character classes")


def _validate_handle(handle: str) -> None:
    if not re.fullmatch(r"@[A-Za-z0-9_]{3,31}", handle):
        raise HTTPException(status_code=400, detail="invalid handle format")


def _extract_bearer_token(auth_header: str | None) -> str:
    if not auth_header:
        raise HTTPException(status_code=401, detail="Authorization header is missing")
    prefix = "Bearer "
    if not auth_header.startswith(prefix):
        raise HTTPException(status_code=401, detail="Invalid authorization scheme")
    token = auth_header[len(prefix):].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Access token is missing")
    return token


def _current_user_from_header(authorization: str | None, db: Session) -> User:
    token = _extract_bearer_token(authorization)
    try:
        payload = decode_access_token(token)
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="invalid access token")
    if payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="invalid token type")
    user_id = str(payload.get("sub", ""))
    if not user_id:
        raise HTTPException(status_code=401, detail="invalid token subject")

    user = db.get(User, user_id)
    if not user or user.deleted_at is not None:
        raise HTTPException(status_code=401, detail="user not found")
    return user


def _issue_auth_response(user: User, db: Session, device_id: str) -> AuthResponse:
    access_token = create_access_token(user.id)
    refresh_token, refresh_hash, expires_at = create_refresh_token()

    token_row = RefreshToken(
        id=str(uuid.uuid4()),
        user_id=user.id,
        token_hash=refresh_hash,
        device_id=device_id,
        expires_at=expires_at,
    )
    db.add(token_row)
    db.commit()

    return AuthResponse(
        user=MeResponse(
            id=user.id,
            handle=user.handle,
            display_name=user.display_name,
            email=user.email,
        ),
        access_token=access_token,
        refresh_token=refresh_token,
    )


@app.post("/v1/auth/signup", response_model=AuthResponse)
def signup(payload: SignupRequest, db: Session = Depends(get_db)) -> AuthResponse:
    email = _normalize_email(payload.email)
    handle = _normalize_handle(payload.handle)

    if not email:
        raise HTTPException(status_code=400, detail="email is required")
    if not payload.display_name.strip():
        raise HTTPException(status_code=400, detail="display_name is required")
    _validate_password_strength(payload.password)
    _validate_handle(handle)

    email_exists = db.scalar(select(User.id).where(User.email == email))
    if email_exists:
        raise HTTPException(status_code=409, detail="email already exists")
    handle_exists = db.scalar(select(User.id).where(User.handle == handle))
    if handle_exists:
        raise HTTPException(status_code=409, detail="handle already exists")

    user = User(
        id=str(uuid.uuid4()),
        email=email,
        handle=handle,
        display_name=payload.display_name.strip(),
        password_hash=hash_password(payload.password),
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="email or handle already exists")
    db.refresh(user)

    return _issue_auth_response(user, db, payload.device_id or "ios-device")


@app.post("/v1/auth/login", response_model=AuthResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> AuthResponse:
    email = _normalize_email(payload.email)
    user = db.scalar(select(User).where(and_(User.email == email, User.deleted_at.is_(None))))
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="invalid email or password")
    return _issue_auth_response(user, db, payload.device_id)


@app.post("/v1/auth/refresh", response_model=AuthResponse)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)) -> AuthResponse:
    refresh_hash = hash_refresh_token(payload.refresh_token)
    token_row = db.scalar(
        select(RefreshToken).where(
            and_(
                RefreshToken.token_hash == refresh_hash,
                RefreshToken.device_id == payload.device_id,
                RefreshToken.revoked_at.is_(None),
            )
        )
    )
    if not token_row:
        raise HTTPException(status_code=401, detail="invalid refresh token")
    if token_row.expires_at < utc_now():
        raise HTTPException(status_code=401, detail="refresh token expired")

    user = db.get(User, token_row.user_id)
    if not user or user.deleted_at is not None:
        raise HTTPException(status_code=401, detail="user not found")

    token_row.revoked_at = utc_now()
    db.commit()
    return _issue_auth_response(user, db, payload.device_id)


@app.post("/v1/auth/logout")
def logout(
    payload: LogoutRequest,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> dict[str, str]:
    user = _current_user_from_header(authorization, db)
    now = utc_now()

    if payload.refresh_token:
        refresh_hash = hash_refresh_token(payload.refresh_token)
        token_row = db.scalar(
            select(RefreshToken).where(
                and_(
                    RefreshToken.user_id == user.id,
                    RefreshToken.token_hash == refresh_hash,
                    RefreshToken.revoked_at.is_(None),
                )
            )
        )
        if token_row:
            token_row.revoked_at = now
    else:
        rows = db.scalars(
            select(RefreshToken).where(
                and_(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
            )
        ).all()
        for row in rows:
            row.revoked_at = now
    db.commit()
    return {"status": "ok"}


@app.get("/v1/auth/me", response_model=MeResponse)
def me(authorization: str | None = Header(default=None), db: Session = Depends(get_db)) -> MeResponse:
    user = _current_user_from_header(authorization, db)
    return MeResponse(
        id=user.id,
        handle=user.handle,
        display_name=user.display_name,
        email=user.email,
    )


@app.get("/v1/friends", response_model=list[FriendSummaryResponse])
def list_friends(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> list[FriendSummaryResponse]:
    me_user = _current_user_from_header(authorization, db)

    friend_ids = db.scalars(
        select(Friendship.friend_user_id).where(Friendship.user_id == me_user.id)
    ).all()
    if not friend_ids:
        return []

    rows = db.scalars(
        select(User)
        .where(
            and_(
                User.deleted_at.is_(None),
                User.id.in_(list(friend_ids)),
            )
        )
        .order_by(User.handle.asc())
    ).all()
    return [
        FriendSummaryResponse(
            id=row.id,
            handle=row.handle,
            display_name=row.display_name,
        )
        for row in rows
    ]


@app.post("/v1/friends", response_model=FriendSummaryResponse)
def add_friend(
    payload: FriendAddRequest,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> FriendSummaryResponse:
    me_user = _current_user_from_header(authorization, db)
    target_id = payload.user_id.strip()
    if not target_id:
        raise HTTPException(status_code=400, detail="user_id is required")
    if target_id == me_user.id:
        raise HTTPException(status_code=400, detail="cannot add yourself")

    target_user = db.get(User, target_id)
    if not target_user or target_user.deleted_at is not None:
        raise HTTPException(status_code=404, detail="user not found")

    existing = db.scalar(
        select(Friendship).where(
            and_(
                Friendship.user_id == me_user.id,
                Friendship.friend_user_id == target_id,
            )
        )
    )
    if not existing:
        db.add(Friendship(user_id=me_user.id, friend_user_id=target_id))
        db.commit()

    return FriendSummaryResponse(
        id=target_user.id,
        handle=target_user.handle,
        display_name=target_user.display_name,
    )


@app.delete("/v1/friends/{friend_user_id}")
def remove_friend(
    friend_user_id: str,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> dict[str, str]:
    me_user = _current_user_from_header(authorization, db)
    row = db.scalar(
        select(Friendship).where(
            and_(
                Friendship.user_id == me_user.id,
                Friendship.friend_user_id == friend_user_id,
            )
        )
    )
    if row:
        db.delete(row)
        db.commit()
    return {"status": "ok"}


def _ensure_member(db: Session, conversation_id: str, user_id: str) -> None:
    row = db.scalar(
        select(ConversationMember).where(
            and_(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
        )
    )
    if not row:
        raise HTTPException(status_code=403, detail="not a conversation member")


@app.post("/v1/conversations", response_model=ConversationSummaryResponse)
def create_conversation(
    payload: ConversationCreateRequest,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> ConversationSummaryResponse:
    user = _current_user_from_header(authorization, db)
    kind = payload.kind.strip().lower()
    if kind != "dm":
        raise HTTPException(status_code=400, detail="only dm conversations are supported")
    if len(payload.member_ids) != 1:
        raise HTTPException(status_code=400, detail="dm requires exactly one friend user id")

    member_ids = set(payload.member_ids)
    member_ids.add(user.id)
    if len(member_ids) != 2:
        raise HTTPException(status_code=400, detail="invalid member set")

    # 同じ2人なら既存会話を再利用
    user_conversations = db.scalars(
        select(ConversationMember.conversation_id).where(
            ConversationMember.user_id.in_(list(member_ids))
        )
    ).all()
    for conv_id in set(user_conversations):
        members = db.scalars(
            select(ConversationMember.user_id).where(ConversationMember.conversation_id == conv_id)
        ).all()
        if set(members) == member_ids:
            conv = db.get(Conversation, conv_id)
            if conv and conv.kind == "dm":
                return ConversationSummaryResponse(
                    id=conv.id,
                    kind=conv.kind,
                    title=conv.title,
                    last_message=None,
                    unread_count=0,
                )

    conv = Conversation(
        id=str(uuid.uuid4()),
        kind=kind,
        title=payload.title.strip() if payload.title else None,
        created_by=user.id,
    )
    db.add(conv)
    db.flush()

    for uid in member_ids:
        exists = db.get(User, uid)
        if not exists:
            db.rollback()
            raise HTTPException(status_code=404, detail=f"user not found: {uid}")
        db.add(
            ConversationMember(
                conversation_id=conv.id,
                user_id=uid,
                role="owner" if uid == user.id else "member",
            )
        )

    db.commit()
    return ConversationSummaryResponse(
        id=conv.id,
        kind=conv.kind,
        title=conv.title,
        last_message=None,
        unread_count=0,
    )


@app.delete("/v1/conversations/{conversation_id}")
def delete_conversation(
    conversation_id: str,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> dict[str, str]:
    user = _current_user_from_header(authorization, db)
    _ensure_member(db, conversation_id, user.id)

    conv = db.get(Conversation, conversation_id)
    if not conv:
        raise HTTPException(status_code=404, detail="conversation not found")

    db.delete(conv)
    db.commit()
    return {"status": "ok"}


@app.get("/v1/conversations", response_model=list[ConversationSummaryResponse])
def list_conversations(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> list[ConversationSummaryResponse]:
    user = _current_user_from_header(authorization, db)
    member_rows = db.scalars(
        select(ConversationMember).where(ConversationMember.user_id == user.id)
    ).all()

    result: list[ConversationSummaryResponse] = []
    for member in member_rows:
        conv = db.get(Conversation, member.conversation_id)
        if not conv:
            continue
        last_msg = db.scalar(
            select(Message.body)
            .where(
                and_(
                    Message.conversation_id == conv.id,
                    Message.deleted_at.is_(None),
                )
            )
            .order_by(Message.created_at.desc())
            .limit(1)
        )
        result.append(
            ConversationSummaryResponse(
                id=conv.id,
                kind=conv.kind,
                title=conv.title,
                last_message=last_msg,
                unread_count=0,
            )
        )
    result.sort(key=lambda x: x.id, reverse=True)
    return result


@app.get("/v1/conversations/{conversation_id}/messages", response_model=list[MessageResponse])
def list_messages(
    conversation_id: str,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> list[MessageResponse]:
    user = _current_user_from_header(authorization, db)
    _ensure_member(db, conversation_id, user.id)

    rows = db.scalars(
        select(Message)
        .where(
            and_(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            )
        )
        .order_by(Message.created_at.asc())
    ).all()
    return [
        MessageResponse(
            id=row.id,
            conversation_id=row.conversation_id,
            sender_id=row.sender_id,
            body=row.body,
            original_body=row.original_body,
            kind=row.kind,
            created_at=row.created_at,
        )
        for row in rows
    ]


@app.post("/v1/conversations/{conversation_id}/messages", response_model=MessageResponse)
def create_message(
    conversation_id: str,
    payload: MessageCreateRequest,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> MessageResponse:
    user = _current_user_from_header(authorization, db)
    _ensure_member(db, conversation_id, user.id)

    existing = db.scalar(
        select(Message).where(
            and_(
                Message.conversation_id == conversation_id,
                Message.client_message_id == payload.client_message_id,
            )
        )
    )
    if existing:
        return MessageResponse(
            id=existing.id,
            conversation_id=existing.conversation_id,
            sender_id=existing.sender_id,
            body=existing.body,
            original_body=existing.original_body,
            kind=existing.kind,
            created_at=existing.created_at,
        )

    row = Message(
        id=str(uuid.uuid4()),
        conversation_id=conversation_id,
        sender_id=user.id,
        client_message_id=payload.client_message_id,
        body=payload.body,
        original_body=payload.original_body,
        kind=payload.kind,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return MessageResponse(
        id=row.id,
        conversation_id=row.conversation_id,
        sender_id=row.sender_id,
        body=row.body,
        original_body=row.original_body,
        kind=row.kind,
        created_at=row.created_at,
    )


def _looks_like_admonition(text: str) -> bool:
    normalized = text.strip()
    if not normalized:
        return True
    return any(phrase in normalized for phrase in ADMONITION_PHRASES)


def _call_gemini(prompt: str, api_key: str) -> dict:
    req_body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0.2},
        "safetySettings": [
            {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"},
        ],
    }
    req_data = json.dumps(req_body).encode("utf-8")
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent?key={api_key}"
    )
    http_req = request.Request(
        url,
        data=req_data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        ssl_context = ssl.create_default_context(cafile=certifi.where())
        with request.urlopen(http_req, timeout=20, context=ssl_context) as resp:
            raw = resp.read().decode("utf-8")
    except error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="ignore")
        raise HTTPException(status_code=502, detail=f"Gemini HTTPError: {detail}") from e
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Gemini request failed: {e}") from e

    try:
        parsed = json.loads(raw)
        text = parsed["candidates"][0]["content"]["parts"][0]["text"]
        return json.loads(text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Gemini response parse failed: {e}") from e


def _call_gemini_text(prompt: str, api_key: str) -> str:
    req_body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.2},
        "safetySettings": [
            {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"},
            {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"},
        ],
    }
    req_data = json.dumps(req_body).encode("utf-8")
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent?key={api_key}"
    )
    http_req = request.Request(
        url,
        data=req_data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        ssl_context = ssl.create_default_context(cafile=certifi.where())
        with request.urlopen(http_req, timeout=20, context=ssl_context) as resp:
            raw = resp.read().decode("utf-8")
        parsed = json.loads(raw)
        return parsed["candidates"][0]["content"]["parts"][0]["text"].strip()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Gemini retry failed: {e}") from e


@app.post("/v1/messages/analyze", response_model=AnalyzeResponse)
def analyze_message(payload: AnalyzeRequest) -> AnalyzeResponse:
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(status_code=500, detail="GEMINI_API_KEY is missing")

    prompt = f"""あなたは「攻撃的な日本語を、意味を保ったまま丁寧な日本語へ通訳するエンジン」です。
説教や注意はせず、必ず「通訳結果」を返してください。
以下の入力文を評価し、必ずJSONのみで返答してください。コードブロックは禁止。

入力文:
{payload.text}

出力JSONスキーマ:
{{
  "should_review": true/false,
  "severity": "low|medium|high",
  "emotion": "neutral|anger|sadness|anxiety|joy",
  "detected_expressions": ["..."],
  "suggested_text": "...",
  "reasons": ["..."],
  "analysis_summary": "..."
}}

要件:
- 元の意図・強さを保ちつつ、暴言/侮辱/威圧を避けた丸い言い方へ変換
- 単語1つ（例: バカ）でも必ず通訳結果を返す
- 「そんなことを言ってはいけません」等の説教文は出さない
- 問題がない場合は suggested_text を原文のまま返してよい
- reasons は1件以上

変換例:
- 入力: バカ野郎
- 出力 suggested_text: 落ち着いて話し合いたいです。
"""
    result = _call_gemini(prompt, api_key)

    suggested_text = str(result.get("suggested_text", "")).strip()
    if _looks_like_admonition(suggested_text):
        retry_prompt = f"""あなたは日本語の通訳者です。次の文を、同じ意味のまま、角が立たない言い方に変換してください。
禁止: 説教・注意・規範説明
必須: 変換後の文だけ返す

入力:
{payload.text}
"""
        direct_text = _call_gemini_text(retry_prompt, api_key)
        if direct_text and not _looks_like_admonition(direct_text):
            suggested_text = direct_text

    try:
        return AnalyzeResponse(
            message_id=payload.message_id,
            should_review=bool(result["should_review"]),
            severity=str(result["severity"]),
            emotion=str(result["emotion"]),
            detected_expressions=[str(x) for x in result.get("detected_expressions", [])],
            original_text=payload.text,
            suggested_text=suggested_text if suggested_text else payload.text,
            reasons=[str(x) for x in result.get("reasons", [])] or ["判定理由を取得できませんでした"],
            analysis_summary=str(result["analysis_summary"]),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Gemini schema mismatch: {e}") from e
