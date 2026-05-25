import csv
import io
from datetime import date
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..database import get_db

router = APIRouter(prefix="/ventas", tags=["ventas"])

QUERIES_DIR = Path(__file__).resolve().parent.parent / "queries"

# Límites globales
DEFAULT_LIMIT = 1000
MAX_LIMIT = 5000
CSV_CHUNK_SIZE = 1000  # filas por chunk al hacer streaming


def _load_query(name: str) -> str:
    path = QUERIES_DIR / name
    if not path.exists():
        raise HTTPException(status_code=500, detail=f"Query no encontrada: {name}")
    return path.read_text(encoding="utf-8")


def _paginate_sql(sql: str) -> str:
    """Añade SELECT con COUNT OVER + OFFSET/FETCH a una query que termina en CTE 'data'."""
    base = sql.rstrip().rstrip(";")
    return base + """
SELECT *, COUNT(*) OVER() AS _total_rows
FROM data
ORDER BY (SELECT NULL)
OFFSET :_offset ROWS FETCH NEXT :_limit ROWS ONLY;
"""


def _full_sql(sql: str) -> str:
    """Añade SELECT * FROM data al final de una query que termina en CTE 'data'."""
    base = sql.rstrip().rstrip(";")
    return base + "\nSELECT * FROM data;\n"


def _stream_csv(db: Session, sql: str, params: dict, filename: str):
    """Ejecuta SQL y devuelve un StreamingResponse en CSV."""
    full = _full_sql(sql)
    stmt = text(full).execution_options(stream_results=True, yield_per=CSV_CHUNK_SIZE)
    result = db.execute(stmt, params)
    keys = list(result.keys())

    def generate():
        buffer = io.StringIO()
        writer = csv.writer(buffer, quoting=csv.QUOTE_MINIMAL)
        writer.writerow(keys)
        yield buffer.getvalue()
        buffer.seek(0)
        buffer.truncate(0)

        for chunk in result.partitions(CSV_CHUNK_SIZE):
            for row in chunk:
                writer.writerow(row)
            data = buffer.getvalue()
            buffer.seek(0)
            buffer.truncate(0)
            yield data

    headers = {"Content-Disposition": f'attachment; filename="{filename}"'}
    return StreamingResponse(generate(), media_type="text/csv; charset=utf-8", headers=headers)


def _run_paginated(db: Session, sql: str, params: dict, limit: int, offset: int):
    """Ejecuta SQL paginada y devuelve dict con metadata + data."""
    paginated_sql = _paginate_sql(sql)
    paginated_params = {**params, "_limit": limit, "_offset": offset}
    rows = db.execute(text(paginated_sql), paginated_params).mappings().all()
    if rows:
        total = rows[0]["_total_rows"]
        data = [{k: v for k, v in dict(r).items() if k != "_total_rows"} for r in rows]
    else:
        total = 0
        data = []
    has_more = (offset + len(data)) < total
    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "count": len(data),
        "has_more": has_more,
        "next_offset": offset + limit if has_more else None,
        "data": data,
    }


# ---------------------------------------------------------------------------
# /ventas/poscarnes
# ---------------------------------------------------------------------------
@router.get(
    "/poscarnes",
    summary="Ventas Diarias POS Carnes",
    description=(
        "Resumen diario de ventas del POS de carnes (t9930). "
        "Soporta paginación (limit/offset) y descarga CSV (format=csv)."
    ),
)
def ventas_poscarnes(
    fecha_inicio: date = Query(..., description="Fecha inicial (inclusiva), YYYY-MM-DD"),
    fecha_fin: date = Query(..., description="Fecha final (exclusiva), YYYY-MM-DD"),
    id_cia: Optional[int] = Query(None, description="Código compañía (4,5,6,7). Omitir = todas"),
    id_co: Optional[str] = Query(None, description="Código centro operación. Omitir = todos"),
    referencia: Optional[str] = Query(None, description="Referencia producto. Omitir = todos"),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT, description="Máx filas por página (1-5000)"),
    offset: int = Query(0, ge=0, description="Filas a saltar (paginación)"),
    format: Optional[str] = Query(
        None,
        description="Omitir = JSON paginado. 'csv' = descarga completa en streaming.",
        pattern="^(csv)$",
    ),
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
        if format == "csv":
            fname = f"poscarnes_{fecha_inicio}_{fecha_fin}.csv"
            return _stream_csv(db, sql, params, fname)
        return _run_paginated(db, sql, params, limit, offset)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ---------------------------------------------------------------------------
# /ventas/agropecuaria
# ---------------------------------------------------------------------------
@router.get(
    "/agropecuaria",
    summary="Ventas Diarias Agropecuaria",
    description=(
        "Ventas diarias del módulo agropecuario (t470) con grupo, especie, proceso, "
        "vendedor y cliente. Soporta paginación (limit/offset) y descarga CSV (format=csv)."
    ),
)
def ventas_agropecuaria(
    fecha_inicio: date = Query(..., description="Fecha inicial (inclusiva), YYYY-MM-DD"),
    fecha_fin: date = Query(..., description="Fecha final (exclusiva), YYYY-MM-DD"),
    id_cia: int = Query(..., description="Código compañía (3,4,5,6,7). Requerido"),
    id_co: Optional[str] = Query(None, description="Código centro operación. Omitir = todos"),
    referencia: Optional[str] = Query(None, description="Referencia producto. Omitir = todas"),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT, description="Máx filas por página (1-5000)"),
    offset: int = Query(0, ge=0, description="Filas a saltar (paginación)"),
    format: Optional[str] = Query(
        None,
        description="Omitir = JSON paginado. 'csv' = descarga completa en streaming.",
        pattern="^(csv)$",
    ),
    db: Session = Depends(get_db),
):
    sql = _load_query("ventas_carnicos.sql")
    params = {
        "fecha_inicio": fecha_inicio,
        "fecha_fin": fecha_fin,
        "id_cia": id_cia,
        "id_co": id_co,
        "referencia": referencia,
    }
    try:
        if format == "csv":
            fname = f"agropecuaria_{fecha_inicio}_{fecha_fin}_cia{id_cia}.csv"
            return _stream_csv(db, sql, params, fname)
        return _run_paginated(db, sql, params, limit, offset)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
