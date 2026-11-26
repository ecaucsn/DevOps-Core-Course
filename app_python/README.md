# DevOps Info Service

## Обзор

Небольшой HTTP-сервис на FastAPI, который возвращает метаданные о самом сервисе и
о хосте, на котором он запущен, а также дешёвый эндпоинт проверки состояния. Это
основа проекта, который в последующих лабораторных контейнеризуется, покрывается
CI, разворачивается в Kubernetes и доставляется через GitOps.

Схема эволюции сервиса: [`docs/architecture.md`](docs/architecture.md).

## Требования

- Python 3.13 (минимум 3.11)
- Linux, macOS или Windows (WSL2)
- `pip` и `venv`

## Установка

```bash
python3.13 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Запуск

```bash
python app.py                              # 0.0.0.0:5000
PORT=8080 python app.py                    # пользовательский порт
HOST=127.0.0.1 PORT=3000 python app.py     # host и порт
```

Проверка:

```bash
curl -s http://localhost:5000/ | jq .
curl -s http://localhost:5000/health | jq .
```

## Эндпоинты API

| Method | Path | Description |
|---|---|---|
| GET | `/` | Полные метаданные сервиса и хоста (JSON) |
| GET | `/health` | Проба состояния: статус, время, uptime |

Пример ответа `/health`:

```json
{
  "status": "ok",
  "timestamp": "2026-11-26T10:41:22.677630+00:00",
  "uptime_seconds": 2
}
```

## Конфигурация

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `HOST` | `0.0.0.0` | Адрес, на котором слушает сервер |
| `PORT` | `5000` | Порт сервера |
| `DEBUG` | `False` | Включает уровень логирования DEBUG (`true`/`false`) |
| `SERVICE_NAME` | `devops-info-service` | Имя сервиса в ответе `/` |
