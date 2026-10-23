import os, secrets, hashlib
from datetime import datetime, timedelta, timezone
from typing import Optional
from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, text
import jwt
from pwdlib import PasswordHash

url = os.getenv("DATABASE_URL", "")
if url.startswith("postgres://"):
    url = url.replace("postgres://", "postgresql://", 1)
engine = create_engine(url, pool_pre_ping=True) if url else None
JWT_SECRET = os.getenv("JWT_SECRET", "")
OWNER_EMAIL = os.getenv("OWNER_EMAIL", "hydraabhinav121@gmail.com").lower()
BOOTSTRAP = os.getenv("OWNER_BOOTSTRAP_TOKEN", "")
passwords = PasswordHash.recommended()
app = FastAPI(title="Insane Straps API", version="1.1")

@app.get("/health")
def health():
    checks = {"database_configured": engine is not None, "jwt_configured": bool(JWT_SECRET), "owner_bootstrap_configured": bool(BOOTSTRAP)}
    if engine is not None:
        try:
            with engine.connect() as c:
                c.execute(text("SELECT 1"))
            checks["database_reachable"] = True
        except Exception:
            checks["database_reachable"] = False
    else:
        checks["database_reachable"] = False
    checks["ready"] = checks["database_reachable"] and checks["jwt_configured"]
    return checks

def db():
    if engine is None:
        raise HTTPException(503, "Database is not configured")
    return engine.begin()

def audit(c, action, username=None, detail=None):
    c.execute(text("INSERT INTO audit_logs(action,username,detail) VALUES(:a,:u,:d)"),
              {"a": action, "u": username, "d": detail})

@app.on_event("startup")
def init_db():
    if engine is None:
        return
    with engine.begin() as c:
        c.execute(text("CREATE TABLE IF NOT EXISTS users(id BIGSERIAL PRIMARY KEY, username TEXT UNIQUE NOT NULL, email TEXT UNIQUE, password_hash TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'user', pro_until TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())"))
        c.execute(text("CREATE TABLE IF NOT EXISTS premium_keys(id BIGSERIAL PRIMARY KEY, key_hash TEXT UNIQUE NOT NULL, duration_days INT NOT NULL, redeemed_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), redeemed_at TIMESTAMPTZ)"))
        c.execute(text("CREATE TABLE IF NOT EXISTS audit_logs(id BIGSERIAL PRIMARY KEY, action TEXT NOT NULL, username TEXT, detail TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())"))

class Signup(BaseModel):
    username: str = Field(min_length=3, max_length=32, pattern=r"^[A-Za-z0-9_.-]+$")
    password: str = Field(min_length=10, max_length=128)
    email: Optional[str] = None
class Login(BaseModel):
    username: str
    password: str
class OwnerSetup(BaseModel):
    token: str
    username: str = Field(min_length=3, max_length=32, pattern=r"^[A-Za-z0-9_.-]+$")
    password: str = Field(min_length=12, max_length=128)
class KeyCreate(BaseModel):
    duration_days: int = Field(ge=1, le=3650)
class Redeem(BaseModel):
    key: str = Field(min_length=12, max_length=128)

def issue(u):
    if not JWT_SECRET:
        raise HTTPException(503, "JWT_SECRET is not configured")
    return jwt.encode({"sub": u["username"], "role": u["role"],
      "exp": datetime.now(timezone.utc) + timedelta(hours=12)}, JWT_SECRET, algorithm="HS256")

def current(authorization: Optional[str] = Header(None)):
    if not JWT_SECRET:
        raise HTTPException(503, "Authentication is not configured")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Sign in required")
    try:
        p = jwt.decode(authorization[7:], JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise HTTPException(401, "Invalid or expired session")
    return {"username": p["sub"], "role": p["role"]}

def owner(u=Depends(current)):
    if u["role"] != "owner":
        raise HTTPException(403, "Owner access required")
    return u

@app.get("/health")
def health():
    return {"ok": True, "database_configured": engine is not None, "auth_configured": bool(JWT_SECRET)}

@app.post("/auth/signup", status_code=201)
def signup(b: Signup):
    with db() as c:
        exists = c.execute(text("SELECT 1 FROM users WHERE lower(username)=lower(:u) OR (:e IS NOT NULL AND lower(email)=lower(:e))"), {"u": b.username, "e": b.email}).first()
        if exists:
            raise HTTPException(409, "Username or email already exists")
        c.execute(text("INSERT INTO users(username,email,password_hash) VALUES(:u,:e,:p)"), {"u": b.username, "e": b.email.lower() if b.email else None, "p": passwords.hash(b.password)})
        audit(c, "account_created", b.username)
    u = {"username": b.username, "role": "user"}
    return {"token": issue(u), "user": u}

@app.post("/auth/login")
def login(b: Login):
    with db() as c:
        row = c.execute(text("SELECT username,password_hash,role,pro_until FROM users WHERE lower(username)=lower(:u)"), {"u": b.username}).mappings().first()
        if not row or not passwords.verify(b.password, row["password_hash"]):
            audit(c, "login_failed", b.username)
            raise HTTPException(401, "Invalid username or password")
        audit(c, "login_succeeded", row["username"])
        u = {"username": row["username"], "role": row["role"]}
        pro = bool(row["pro_until"] and row["pro_until"] > datetime.now(timezone.utc))
    return {"token": issue(u), "user": u, "is_pro": pro}

@app.post("/admin/bootstrap")
def bootstrap(b: OwnerSetup):
    if not BOOTSTRAP or not secrets.compare_digest(b.token, BOOTSTRAP):
        raise HTTPException(403, "Invalid owner setup token")
    with db() as c:
        if c.execute(text("SELECT 1 FROM users WHERE role='owner' LIMIT 1")).first():
            raise HTTPException(409, "Owner already initialized")
        if c.execute(text("SELECT 1 FROM users WHERE lower(email)=lower(:e) OR lower(username)=lower(:u)"), {"e": OWNER_EMAIL, "u": b.username}).first():
            raise HTTPException(409, "Owner email or username already exists")
        c.execute(text("INSERT INTO users(username,email,password_hash,role) VALUES(:u,:e,:p,'owner')"), {"u": b.username, "e": OWNER_EMAIL, "p": passwords.hash(b.password)})
        audit(c, "owner_initialized", b.username)
    return {"message": "Owner created. Remove OWNER_BOOTSTRAP_TOKEN after setup."}

@app.get("/owner/users")
def users(u=Depends(owner)):
    with db() as c:
        rows = c.execute(text("SELECT username,email,role,pro_until,created_at FROM users ORDER BY created_at DESC LIMIT 1000")).mappings().all()
    return {"users": [dict(x) for x in rows]}

@app.get("/owner/logs")
def logs(u=Depends(owner)):
    with db() as c:
        rows = c.execute(text("SELECT action,username,detail,created_at FROM audit_logs ORDER BY created_at DESC LIMIT 1000")).mappings().all()
    return {"logs": [dict(x) for x in rows]}

@app.post("/owner/keys")
def create_key(b: KeyCreate, u=Depends(owner)):
    raw = "IS-" + secrets.token_urlsafe(24)
    with db() as c:
        c.execute(text("INSERT INTO premium_keys(key_hash,duration_days) VALUES(:h,:d)"), {"h": hashlib.sha256(raw.encode()).hexdigest(), "d": b.duration_days})
        audit(c, "premium_key_created", u["username"], "days=" + str(b.duration_days))
    return {"key": raw, "duration_days": b.duration_days, "warning": "Copy now; plaintext is not stored."}

@app.post("/keys/redeem")
def redeem(b: Redeem, u=Depends(current)):
    with db() as c:
        k = c.execute(text("SELECT id,duration_days FROM premium_keys WHERE key_hash=:h AND redeemed_by IS NULL FOR UPDATE"), {"h": hashlib.sha256(b.key.encode()).hexdigest()}).mappings().first()
        if not k:
            audit(c, "premium_key_rejected", u["username"])
            raise HTTPException(400, "Invalid or already redeemed key")
        c.execute(text("UPDATE premium_keys SET redeemed_by=:u,redeemed_at=NOW() WHERE id=:id"), {"u": u["username"], "id": k["id"]})
        c.execute(text("UPDATE users SET pro_until=GREATEST(COALESCE(pro_until,NOW()),NOW()) + (:d * INTERVAL '1 day') WHERE username=:u"), {"d": k["duration_days"], "u": u["username"]})
        audit(c, "premium_key_redeemed", u["username"], "days=" + str(k["duration_days"]))
    return {"message": "Premium activated", "duration_days": k["duration_days"]}

class LinkEmail(BaseModel):
    email: str = Field(min_length=5, max_length=254, pattern=r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

@app.post("/account/email")
def link_email(b: LinkEmail, u=Depends(current)):
    email = b.email.strip().lower()
    with db() as c:
        exists = c.execute(text("SELECT 1 FROM users WHERE lower(email)=:e AND username<>:u"), {"e": email, "u": u["username"]}).first()
        if exists:
            raise HTTPException(409, "Email is already linked to another account")
        c.execute(text("UPDATE users SET email=:e WHERE username=:u"), {"e": email, "u": u["username"]})
        audit(c, "email_linked", u["username"])
    return {"message": "Email linked. Verify this address before relying on it for account recovery."}

@app.get("/owner/keys")
def list_keys(u=Depends(owner)):
    with db() as c:
        rows = c.execute(text("SELECT id,duration_days,redeemed_by,created_at,redeemed_at FROM premium_keys ORDER BY created_at DESC LIMIT 500")).mappings().all()
    return {"keys": [dict(x) for x in rows]}

@app.delete("/owner/keys/{key_id}")
def revoke_key(key_id: int, u=Depends(owner)):
    with db() as c:
        row = c.execute(text("SELECT id,redeemed_by FROM premium_keys WHERE id=:id"), {"id": key_id}).mappings().first()
        if not row:
            raise HTTPException(404, "Premium key not found")
        if row["redeemed_by"]:
            raise HTTPException(409, "Already redeemed keys cannot be revoked")
        c.execute(text("DELETE FROM premium_keys WHERE id=:id"), {"id": key_id})
        audit(c, "premium_key_revoked", u["username"], "key_id=" + str(key_id))
    return {"message": "Unused premium key revoked"}

@app.get("/me")
def me(u=Depends(current)):
    with db() as c:
        row = c.execute(text("SELECT username,email,role,pro_until,created_at FROM users WHERE username=:u"), {"u": u["username"]}).mappings().first()
    if not row:
        raise HTTPException(404, "Account not found")
    result = dict(row)
    result["is_pro"] = result["role"] == "owner" or bool(result["pro_until"] and result["pro_until"] > datetime.now(timezone.utc))
    return result
