# Лабораторная 1 — отчёт о сдаче

**Студент:** Андрей
**GitHub username (первая строка для проверки):** ecaucsn
**Ветка:** `lab01`

---

## 1. Выбор фреймворка

Выбран **FastAPI 0.165** — современный ASGI-фреймворк с нативной поддержкой async,
автоматической документацией OpenAPI (`/docs`, `/redoc`) и валидацией через Pydantic.
Для сервиса, который будет расти и станет частью портфолио, автогенерируемая
OpenAPI-спецификация и типизация дают лучшую поддерживаемость, чем ручные маршруты.

| Критерий | Flask 3.1 | FastAPI 0.165 | Django 5.2 |
|---|---|---|---|
| Размер / «вес» | минимальный микрофреймворк | средний, ASGI-стек | крупный full-stack |
| Async | ограниченно (WSGI) | нативно (async/await) | частично (sync по умолчанию) |
| OpenAPI / документация | вручную или расширения | автогенерация `/docs` + OpenAPI | через DRF/сторонние пакеты |
| Кривая обучения | низкая | низко-средняя (нужна типизация) | высокая (много компонентов) |
| Уместность для этой задачи | подходит | оптимально | избыточно |

## 2. Применённые лучшие практики

- **Изолированное окружение `venv`** — зависимости проекта не смешиваются с системными.
- **Точное закрепление версий** в `requirements.txt` (`==`) — воспроизводимые сборки.
- **Конфигурация через переменные окружения** (`HOST`, `PORT`, `DEBUG`, `SERVICE_NAME`) — один и тот же код работает в dev/prod без правок.
- **Корректный парсинг булевых значений** (`DEBUG`: сравнение строки в нижнем регистре) — `bool("False")` в Python равен `True`.
- **Timezone-aware даты** (`datetime.now(timezone.utc)`) — исключает `TypeError` при вычитании naive/aware и даёт корректный uptime.
- **Единый JSON-формат ошибок** для 404/500 — API-клиенты не получают HTML.
- **Логирование через `logging`** с временем и уровнем, без `print()` — готово к сбору логов в Loki (лаб. 7).
- **Дешёвый `/health`** без БД и внешних вызовов — станет liveness/readiness-пробой в лаб. 9.
- **`.gitignore`** покрывает `__pycache__`, `*.pyc`, `venv`, логи и артефакты IDE/ОС.
- **`README.md` и этот отчёт** — документация как часть результата.

## 3. Документация API

### `GET /`

Запрос: `curl -s http://localhost:5000/ | jq .`

Ответ (HTTP 200): сервис, система, рантайм, запрос, список эндпоинтов — см. блок
доказательств ниже.

### `GET /health`

Запрос: `curl -s http://localhost:5000/health | jq .`

```json
{
  "status": "ok",
  "timestamp": "2026-11-26T10:41:22.677630+00:00",
  "uptime_seconds": 2
}
```

### Ошибка `404`

Запрос: `curl -s http://localhost:5000/nope | jq .`

```json
{
  "error": "Not Found",
  "status_code": 404,
  "path": "/nope"
}
```

## 4. Свидетельства тестирования

### 4.1 Полный ответ `GET /`

```console
$ curl -s http://localhost:5000/ | jq .
{
  "service": {
    "name": "devops-info-service",
    "version": "1.0.0",
    "description": "DevOps Info Service - metadata about the service and its host",
    "framework": "FastAPI"
  },
  "system": {
    "hostname": "dso",
    "platform": "Linux",
    "platform_version": "#142-Ubuntu SMP PREEMPT_DYNAMIC Wed Sep  2 14:24:27 UTC 2026",
    "architecture": "x86_64",
    "cpu_count": 8,
    "python_version": "3.13.18"
  },
  "runtime": {
    "uptime_seconds": 2,
    "uptime_human": "2 seconds",
    "current_time": "2026-11-26T10:41:22.659883+00:00",
    "timezone": "UTC"
  },
  "request": {
    "client_ip": "127.0.0.1",
    "user_agent": "curl/8.5.0",
    "method": "GET",
    "path": "/"
  },
  "endpoints": [
    { "path": "/", "method": "GET", "description": "Full service and host metadata" },
    { "path": "/health", "method": "GET", "description": "Liveness and readiness probe" }
  ]
}
```

### 4.2 `GET /health`

```console
$ curl -s http://localhost:5000/health | jq .
{
  "status": "ok",
  "timestamp": "2026-11-26T10:41:22.677630+00:00",
  "uptime_seconds": 2
}
```

### 4.3 Обработчик 404 (JSON)

```console
$ curl -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:5000/nope
HTTP 404
$ curl -s http://localhost:5000/nope | jq .
{
  "error": "Not Found",
  "status_code": 404,
  "path": "/nope"
}
```

### 4.4 Переопределение порта через окружение

```console
$ HOST=127.0.0.1 PORT=5050 python app.py
2026-11-26 10:41:26,128 INFO     devops-info-service Starting devops-info-service on 127.0.0.1:5050 (debug=False)

$ curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:5050/health
HTTP 200
```

### 4.5 Логи приложения

```console
2026-11-26 10:41:19,889 INFO     devops-info-service Starting devops-info-service on 0.0.0.0:5000 (debug=False)
INFO:     Started server process [379627]
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:5000 (Press CTRL+C to quit)
2026-11-26 10:41:22,658 INFO     devops-info-service GET / from 127.0.0.1
INFO:     127.0.0.1:33160 - "GET / HTTP/1.1" 200 OK
INFO:     127.0.0.1:33162 - "GET /health HTTP/1.1" 200 OK
INFO:     127.0.0.1:33168 - "GET /nope HTTP/1.1" 404 Not Found
```

### 4.6 Структура проекта

```console
$ find app_python -maxdepth 2 -type f -not -path '*/venv/*' | sort
app_python/.gitignore
app_python/README.md
app_python/app.py
app_python/docs/LAB01.md
app_python/requirements.txt
app_python/tests/__init__.py
```

## 5. Проблемы и решения

**Проблема:** стандартный обработчик 404 во FastAPI/Starlette не гарантировал
единый JSON-формат для всех HTTP-ошибок. **Решение:** зарегистрирован
`@app.exception_handler(StarletteHTTPException)`, который возвращает JSON
`{error, status_code, path}`, и отдельный обработчик `Exception` для 500.

**Проблема:** порт `8080` на рабочей машине занят другим процессом. **Решение:**
для проверки переопределения порта использован свободный `5050`; конфигурация
через `PORT` работает без изменения кода.

## 6. GitHub-сообщество

**GitHub username:** ecaucsn

_<Ответьте своими словами (2–3 предложения): почему звёзды на проекте реально
помогают его мейнтейнерам? Какую конкретную пользу вы получаете, подписываясь на
других разработчиков?>_

Выполненные действия:
- [ ] Поставлена звезда репозиторию курса
- [ ] Поставлена звезда `simple-container-com/api`
- [ ] Подписка на преподавателя и TA
- [ ] Подписка на ≥ 3 однокурсников
