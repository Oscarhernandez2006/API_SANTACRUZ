from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    DB_SERVER: str
    DB_PORT: int = 1433
    DB_NAME: str
    DB_USER: str
    DB_PASSWORD: str
    DB_DRIVER: str = "ODBC Driver 17 for SQL Server"

    # API Keys con scopes. Formato: "token1:scope1,scope2;token2:scope3"
    # Ejemplo: "tok_abc...:ventas;tok_xyz...:terceros;tok_def...:existencias"
    # Si está vacío, no se exige autenticación (modo abierto - solo para desarrollo)
    API_KEYS: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")


settings = Settings()
