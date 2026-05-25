# API Consultas - Carnes Santa Cruz

API FastAPI que consulta SQL Server (Amazon RDS).

## Configuración

1. Edita el archivo `.env` y coloca tu contraseña en `DB_PASSWORD`.
2. Asegúrate de tener instalado el driver **ODBC Driver 17 for SQL Server**
   (Microsoft: https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server).

## Instalación

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Ejecución

```powershell
uvicorn app.main:app --reload
```

Endpoints:
- `GET /` — estado del servicio
- `GET /health/db` — prueba la conexión a SQL Server
- `GET /ventas/resumen` — ejecuta `app/queries/ventas_resumen.sql`

# API_SANTACRUZ
