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
from .db_models import RefreshToken, User
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
