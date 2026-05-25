from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.gzip import GZipMiddleware
from sqlalchemy import text
from sqlalchemy.orm import Session

from .database import get_db
from .routers import ventas

app = FastAPI(title="API Consultas - Carnes Santa Cruz")

# Compresión automática (gzip) para todas las respuestas > 1KB
app.add_middleware(GZipMiddleware, minimum_size=1024)

app.include_router(ventas.router)


@app.get("/")
def root():
    return {"status": "ok", "service": "API Consultas"}


@app.get("/health/db")
def health_db(db: Session = Depends(get_db)):
    try:
        result = db.execute(text("SELECT 1")).scalar()
        return {"db": "ok", "result": result}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB error: {exc}")
