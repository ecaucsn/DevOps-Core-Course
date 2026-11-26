import logging
import os
import platform
import socket
from datetime import datetime, timezone

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

SERVICE_NAME = os.getenv("SERVICE_NAME", "devops-info-service")
SERVICE_VERSION = "1.0.0"
SERVICE_DESCRIPTION = "DevOps Info Service - metadata about the service and its host"
FRAMEWORK = "FastAPI"

HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "5000"))
DEBUG = os.getenv("DEBUG", "False").lower() == "true"

START_TIME = datetime.now(timezone.utc)

logging.basicConfig(
    level=logging.DEBUG if DEBUG else logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s %(message)s",
)
logger = logging.getLogger("devops-info-service")

app = FastAPI(title=SERVICE_NAME, version=SERVICE_VERSION, description=SERVICE_DESCRIPTION)

ENDPOINTS = [
    {"path": "/", "method": "GET", "description": "Full service and host metadata"},
    {"path": "/health", "method": "GET", "description": "Liveness and readiness probe"},
]


def _plural(value: int, unit: str) -> str:
    return f"{value} {unit}" + ("" if value == 1 else "s")


def get_uptime_seconds() -> int:
    return int((datetime.now(timezone.utc) - START_TIME).total_seconds())


def get_uptime_human() -> str:
    total = get_uptime_seconds()
    hours, remainder = divmod(total, 3600)
    minutes, seconds = divmod(remainder, 60)
    parts = []
    if hours:
        parts.append(_plural(hours, "hour"))
    if minutes:
        parts.append(_plural(minutes, "minute"))
    if not parts:
        parts.append(_plural(seconds, "second"))
    return ", ".join(parts)


def get_system_info() -> dict:
    return {
        "hostname": socket.gethostname(),
        "platform": platform.system(),
        "platform_version": platform.version(),
        "architecture": platform.machine(),
        "cpu_count": os.cpu_count(),
        "python_version": platform.python_version(),
    }


def get_request_info(request: Request) -> dict:
    return {
        "client_ip": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
        "method": request.method,
        "path": request.url.path,
    }


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail,
            "status_code": exc.status_code,
            "path": request.url.path,
        },
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error on %s", request.url.path)
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal Server Error",
            "status_code": 500,
            "path": request.url.path,
        },
    )


@app.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "uptime_seconds": get_uptime_seconds(),
    }


@app.get("/")
async def root(request: Request) -> dict:
    logger.info(
        "%s %s from %s",
        request.method,
        request.url.path,
        request.client.host if request.client else "-",
    )
    return {
        "service": {
            "name": SERVICE_NAME,
            "version": SERVICE_VERSION,
            "description": SERVICE_DESCRIPTION,
            "framework": FRAMEWORK,
        },
        "system": get_system_info(),
        "runtime": {
            "uptime_seconds": get_uptime_seconds(),
            "uptime_human": get_uptime_human(),
            "current_time": datetime.now(timezone.utc).isoformat(),
            "timezone": "UTC",
        },
        "request": get_request_info(request),
        "endpoints": ENDPOINTS,
    }


if __name__ == "__main__":
    logger.info("Starting %s on %s:%s (debug=%s)", SERVICE_NAME, HOST, PORT, DEBUG)
    uvicorn.run(app, host=HOST, port=PORT)
