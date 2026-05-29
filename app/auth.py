"""Autenticación por API Key con scopes.

Formato de la variable de entorno API_KEYS:
    "token1:scope1,scope2;token2:scope3"

Ejemplo:
    API_KEYS="tok_abc...:ventas;tok_xyz...:terceros;tok_def...:existencias"

Uso en endpoints:
    @router.get("/...", dependencies=[Depends(require_scope("ventas"))])
"""
import secrets
from typing import Dict, Set

from fastapi import Depends, HTTPException, status
from fastapi.security import APIKeyHeader

from .config import settings

API_KEY_HEADER = "X-API-Key"
api_key_scheme = APIKeyHeader(name=API_KEY_HEADER, auto_error=False)


def _parse_api_keys(raw: str) -> Dict[str, Set[str]]:
    """Convierte 'tok1:s1,s2;tok2:s3' -> {'tok1': {'s1','s2'}, 'tok2': {'s3'}}."""
    keys: Dict[str, Set[str]] = {}
    if not raw or not raw.strip():
        return keys
    for entry in raw.split(";"):
        entry = entry.strip()
        if not entry or ":" not in entry:
            continue
        token, scopes_str = entry.split(":", 1)
        token = token.strip()
        scopes = {s.strip() for s in scopes_str.split(",") if s.strip()}
        if token and scopes:
            keys[token] = scopes
    return keys


_API_KEYS: Dict[str, Set[str]] = _parse_api_keys(settings.API_KEYS)
_AUTH_ENABLED = len(_API_KEYS) > 0


def require_scope(scope: str):
    """Dependencia FastAPI que exige que el token tenga el scope dado."""

    def _checker(api_key: str = Depends(api_key_scheme)) -> str:
        # Si no hay tokens configurados, la API queda abierta (modo dev)
        if not _AUTH_ENABLED:
            return "anonymous"

        if not api_key:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Falta header {API_KEY_HEADER}",
            )

        # Comparación constant-time contra cada token registrado
        matched_scopes = None
        for valid_token, scopes in _API_KEYS.items():
            if secrets.compare_digest(api_key, valid_token):
                matched_scopes = scopes
                break

        if matched_scopes is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="API Key inválida",
            )

        if scope not in matched_scopes:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Token sin permiso para scope '{scope}'",
            )

        return api_key

    return _checker
