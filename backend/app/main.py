"""Klar API: scoped account data with optimistic concurrency and ordered sync log."""
import hashlib
import os
import secrets
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError
from fastapi import Depends, FastAPI, Header, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import ValidationError
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session
from .db import Change, LoginFailure, Record, SessionToken, User, get_db, utcnow
from .schemas import Credentials, KIND_SCHEMAS, Mutation, PushRequest, RefreshRequest

app = FastAPI(title='Klar API', version='1.0.0', docs_url=None if os.getenv('APP_ENV') == 'production' else '/docs')
password_hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()


def aware(dt: datetime) -> datetime:
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt


def create_token(db: Session, user_id: str, kind: str, duration: timedelta) -> str:
    value = secrets.token_urlsafe(48)
    db.add(SessionToken(token_hash=token_hash(value), user_id=user_id,
                        kind=kind, expires_at=utcnow()+duration))
    return value


def tokens(db: Session, user_id: str):
    return {'access_token': create_token(db, user_id, 'access', timedelta(hours=1)),
            'refresh_token': create_token(db, user_id, 'refresh', timedelta(days=30)),
            'token_type': 'bearer', 'expires_in': 3600}


def auth(authorization: str | None = Header(default=None), db: Session = Depends(get_db)) -> User:
    if not authorization or not authorization.lower().startswith('bearer '):
        raise HTTPException(401, 'Anmeldung erforderlich')
    value = authorization[7:].strip()
    row = db.get(SessionToken, token_hash(value))
    if row is None or row.kind != 'access' or row.revoked or aware(row.expires_at) <= utcnow():
        raise HTTPException(401, 'Sitzung abgelaufen')
    user = db.get(User, row.user_id)
    if user is None:
        raise HTTPException(401, 'Benutzerkonto nicht gefunden')
    return user


def check_login_limits(db: Session, key: str):
    limit = utcnow() - timedelta(minutes=15)
    failures = db.scalar(select(func.count(LoginFailure.id)).where(LoginFailure.account_key == key,
                             LoginFailure.created_at >= limit)) or 0
    if failures >= 5:
        raise HTTPException(429, 'Zu viele Anmeldeversuche. Bitte in 15 Minuten erneut versuchen.')


@app.get('/health')
def health():
    return {'status':'ok', 'service':'klar-api'}


@app.post('/v1/auth/register', status_code=201)
def register(body: Credentials, db: Session = Depends(get_db)):
    email = str(body.email).strip().lower()
    if db.scalar(select(User.id).where(User.email == email)):
        raise HTTPException(409, 'E-Mail-Adresse bereits registriert')
    user = User(id=str(uuid4()), email=email, password_hash=password_hasher.hash(body.password))
    db.add(user)
    response = tokens(db, user.id)
    db.commit()
    return response


@app.post('/v1/auth/login')
def login(body: Credentials, db: Session = Depends(get_db)):
    email = str(body.email).strip().lower()
    key = hashlib.sha256(email.encode()).hexdigest()
    check_login_limits(db, key)
    user = db.scalar(select(User).where(User.email == email))
    valid = False
    if user:
        try:
            valid = password_hasher.verify(user.password_hash, body.password)
        except (VerifyMismatchError, VerificationError):
            pass
    if not valid:
        db.add(LoginFailure(account_key=key))
        db.commit()
        raise HTTPException(401, 'Ungültige Anmeldedaten')
    db.execute(delete(LoginFailure).where(LoginFailure.account_key == key))
    response = tokens(db, user.id)
    db.commit()
    return response


@app.post('/v1/auth/refresh')
def refresh(body: RefreshRequest, db: Session = Depends(get_db)):
    row = db.get(SessionToken, token_hash(body.refresh_token))
    if row is None or row.kind != 'refresh' or row.revoked or aware(row.expires_at) <= utcnow():
        raise HTTPException(401, 'Erneute Anmeldung erforderlich')
    row.revoked = True
    response = tokens(db, row.user_id)
    db.commit()
    return response


@app.post('/v1/auth/logout', status_code=204)
def logout(body: RefreshRequest, db: Session = Depends(get_db)):
    row = db.get(SessionToken, token_hash(body.refresh_token))
    if row:
        row.revoked = True
        db.commit()
    return None


@app.get('/v1/me')
def me(user: User = Depends(auth)):
    return {'id':user.id, 'email':user.email}


def serialized(row: Record | Change):
    return {'kind':row.kind,'id':row.id,'version':row.version,'deleted':row.deleted,
            'data':row.data,'updated_at':aware(row.updated_at).isoformat()}


@app.get('/v1/sync/pull')
def pull(after: int = Query(default=0, ge=0), limit: int = Query(default=300, ge=1, le=500),
         user: User = Depends(auth), db: Session = Depends(get_db)):
    rows = db.scalars(select(Change).where(Change.user_id == user.id, Change.seq > after)
                      .order_by(Change.seq).limit(limit)).all()
    return {'changes': [{'seq':r.seq, **serialized(r)} for r in rows],
            'next_cursor': rows[-1].seq if rows else after, 'has_more': len(rows) == limit}


@app.post('/v1/sync/push')
def push(body: PushRequest, user: User = Depends(auth), db: Session = Depends(get_db)):
    keys = [(m.kind, str(m.id)) for m in body.mutations]
    if len(set(keys)) != len(keys):
        raise HTTPException(422, 'Doppelte Datensätze innerhalb eines Pakets')
    applied = []
    for mutation in body.mutations:
        payload = {}
        if not mutation.deleted:
            try:
                payload = KIND_SCHEMAS[mutation.kind].model_validate(mutation.data).model_dump(mode='json')
            except ValidationError as exc:
                raise HTTPException(422, {'entity': mutation.kind, 'errors': exc.errors(include_url=False)})
        key = (user.id, mutation.kind, str(mutation.id))
        row = db.get(Record, key, with_for_update=True)
        server_version = row.version if row else 0
        if mutation.base_version != server_version:
            db.rollback()
            raise HTTPException(409, {'message':'Synchronisationskonflikt', 'server':serialized(row) if row else None,
                                      'kind':mutation.kind,'id':str(mutation.id)})
        now = utcnow()
        if row is None:
            row = Record(user_id=user.id, kind=mutation.kind, id=str(mutation.id),
                         version=1, data=payload, deleted=mutation.deleted, updated_at=now)
            db.add(row)
        else:
            row.version += 1
            row.data = payload
            row.deleted = mutation.deleted
            row.updated_at = now
        db.add(Change(user_id=user.id, kind=row.kind, id=row.id, version=row.version,
                      data=payload, deleted=row.deleted, updated_at=now))
        applied.append(serialized(row))
    db.commit()
    return {'applied':applied}


@app.delete('/v1/account', status_code=204)
def delete_account(user: User = Depends(auth), db: Session = Depends(get_db)):
    """Permanently remove the user's sync data and sessions."""
    db.execute(delete(Change).where(Change.user_id == user.id))
    db.execute(delete(Record).where(Record.user_id == user.id))
    db.execute(delete(SessionToken).where(SessionToken.user_id == user.id))
    db.delete(user)
    db.commit()
    return None
