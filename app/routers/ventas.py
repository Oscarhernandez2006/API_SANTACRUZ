from datetime import date
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..database import get_db

router = APIRouter(prefix="/ventas", tags=["ventas"])

QUERIES_DIR = Path(__file__).resolve().parent.parent / "queries"


def _load_query(name: str) -> str:
    path = QUERIES_DIR / name
    if not path.exists():
        raise HTTPException(status_code=500, detail=f"Query no encontrada: {name}")
    return path.read_text(encoding="utf-8")


@router.get("/resumen")
def ventas_resumen(
    fecha_inicio: date = Query(..., description="Fecha inicial (inclusiva), YYYY-MM-DD"),
    fecha_fin: date = Query(..., description="Fecha final (exclusiva), YYYY-MM-DD"),
    id_cia: Optional[int] = Query(None, description="Código compañía (4,5,6,7). Omitir = todas"),
    id_co: Optional[str] = Query(None, description="Código centro operación. Omitir = todos"),
    referencia: Optional[str] = Query(None, description="Referencia producto. Omitir = todos"),
    db: Session = Depends(get_db),
):
    sql = _load_query("ventas_resumen.sql")
    params = {
        "fecha_inicio": fecha_inicio,
        "fecha_fin": fecha_fin,
        "id_cia": id_cia,
        "id_co": id_co,
        "referencia": referencia,
    }
    try:
        rows = db.execute(text(sql), params).mappings().all()
        return {"count": len(rows), "data": [dict(r) for r in rows]}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
