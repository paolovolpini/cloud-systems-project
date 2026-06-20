import os
import secrets
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, HttpUrl
import psycopg2
import time

app = FastAPI()

def get_conn():
    url = (
        f"postgresql://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}"
        f"@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT', '5432')}/{os.getenv('DB_NAME')}"
    )
    return psycopg2.connect(url)

@app.on_event("startup")
def init_db():
    retries = 10
    for i in range(retries):
        try:
            conn = get_conn()
            with conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT pg_advisory_xact_lock(12345)")
                    cur.execute("""
                        CREATE TABLE IF NOT EXISTS urls (
                            short_code VARCHAR(10) PRIMARY KEY,
                            long_url   TEXT NOT NULL
                        );
                    """)
            conn.close()
            return
        except Exception as e:
            print(f"Retry {i+1}/{retries}: {e}")
            time.sleep(3)
    raise RuntimeError("Impossibile connettersi al database")

class URLRequest(BaseModel):
    url: HttpUrl

def generate_unique_code(conn) -> str:
    for _ in range(10):
        code = secrets.token_urlsafe(5)[:6]
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM urls WHERE short_code = %s", (code,))
            if not cur.fetchone():
                return code
    raise HTTPException(status_code=500, detail="Impossibile generare codice univoco")

@app.post("/api/shorten", status_code=status.HTTP_201_CREATED)
def shorten(payload: URLRequest):
    long_url = str(payload.url)
    if not long_url:
        raise HTTPException(status_code=400, detail="L'URL è obbligatorio")

    conn = get_conn()
    with conn:
        short_code = generate_unique_code(conn) 
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO urls (short_code, long_url) VALUES (%s, %s);",
                (short_code, long_url)
            )
    conn.close()

    return {"short_url": f"/r/{short_code}"}

@app.get("/r/{short_code}")
def redirect_to_long(short_code: str):
    
    conn = get_conn()
    with conn:
        with conn.cursor() as cur:
            cur.execute("SELECT long_url FROM urls WHERE short_code = %s;", (short_code,))
            row = cur.fetchone()
    conn.close()

    if row:
        long_url = row[0]
        return RedirectResponse(url=long_url, status_code=status.HTTP_302_FOUND)

    raise HTTPException(status_code=404, detail="URL non trovato")