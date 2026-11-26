# Лабораторная работа 8 — Метрики и мониторинг с Prometheus

![сложность](https://img.shields.io/badge/difficulty-intermediate-yellow)
![тема](https://img.shields.io/badge/topic-Metrics%20%26%20Monitoring-blue)
![баллы](https://img.shields.io/badge/points-10%2B2-orange)
![технология](https://img.shields.io/badge/tech-Prometheus%203.11%20|%20Grafana%2013%20|%20prometheus--client-informational)

> **Цель:** инструментировать ваше Python-приложение из лабораторной 1 метриками Prometheus, развернуть Prometheus 3.x рядом со стеком Loki прошлой недели для их скрейпинга и спроектировать дашборд Grafana вокруг **метода RED**.
> **Результат сдачи:** PR из ветки `lab08`, добавляющий эндпоинт `/metrics` + инструментацию в `app_python/`, сервис `prometheus` в `monitoring/docker-compose.yml`, `monitoring/prometheus/prometheus.yml`, JSON дашборда RED из 6 панелей и `monitoring/docs/LAB08.md` с захватами доказательств.

---

## Обзор

В лабораторной 7 вы дали сервису глаза (логи). На этой неделе вы даёте ему **пульс** (метрики). Вы:
- Инструментируете HTTP-сервис с помощью `prometheus_client` — объявив **Counter**, **Histogram** и эндпоинт `/metrics`
- Подключите **Prometheus** в стек Compose лабораторной 7, чтобы он забирал `/metrics` у вашего приложения каждые несколько секунд
- Напишете **PromQL** для **метода RED** (Rate / Errors / Duration) — запросы пишете вы, а не копируете
- Спроектируете дашборд Grafana вокруг трёх вопросов RED плюс насыщение
- Укрепите стек: ретенция, лимиты ресурсов, проверки состояния, персистентность

> ⚠️ **Область:** single-binary Prometheus на локальном Docker-хосте. Без Alertmanager, без `remote_write`, без Mimir — это территория после основного курса. Навык — **инструментация + PromQL**, а не запуск федеративного Prometheus.

> ✨ **Замечание о Prometheus 3.x.** Эта лабораторная использует Prometheus 3.11.3 (текущий стабильный на май 2026; 3.5 LTS поддерживается до июля 2026). По сравнению с 2.x он по умолчанию использует имена метрик/меток в UTF-8, поставляет OTLP-приёмник и переводит **нативные гистограммы в GA**. В обязательных задачах вы будете использовать классические гистограммы, а нативные можете попробовать как растяжку.

---

## Состояние проекта

**У вас должно быть из предыдущих лабораторных работ:**
- `app_python/` из лабораторной 1 — сервис Flask/FastAPI с `/` и `/health`
- Рабочий Docker-образ из него из лабораторной 2
- Стек compose `monitoring/` из лабораторной 7 — `loki`, `alloy`, `grafana`, `app`, все в сети `logging`
- Обновление JSON-логирования `app_python/` из лабораторной 7 (эта лабораторная добавляет *ещё один* слой в тот же `app.py`)

**Эта лабораторная работа добавляет:**
- Эндпоинт `/metrics` + инструментацию `Counter` + `Histogram` в `app_python/app.py`
- `monitoring/prometheus/prometheus.yml` — ВЫ заполняете его из скелета
- Сервис `prometheus` в `monitoring/docker-compose.yml` (расширяет лабораторную 7, не заменяет её)
- `monitoring/grafana/dashboards/lab08.json` — ваш экспортированный дашборд RED из 6 панелей
- `monitoring/docs/LAB08.md` — отчёт о сдаче

К лабораторной 16 вы развернёте это как `kube-prometheus-stack` в k3d с CRD `ServiceMonitor`, автоматически обнаруживающими цели. Всё, что вы узнаете на этой неделе — типы метрик, кардинальность, PromQL, RED — переносится дальше без изменений.

---

## Настройка

Версии, используемые в этой лабораторной — зафиксируйте их в вашем compose-файле и `requirements.txt`:

| Компонент | Тег / Версия | Замечания |
|---|---|---|
| `prom/prometheus` | `v3.11.3` | Текущий стабильный (май 2026); `v3.5.0` LTS тоже приемлем |
| `grafana/grafana` | `13.0.1` | Уже в вашем стеке лабораторной 7 |
| `prometheus-client` (Python) | `0.23.1` | Минимум `0.23+`; `0.25.x` — последняя патч-линия |

```bash
docker --version           # 28.x или 29.x
docker compose version     # v2.x
python --version           # 3.12+
```

Раскладка каталогов, которую вы построите:

```
app_python/
├── app.py                            # ВЫ добавляете инструментацию здесь (§1)
└── requirements.txt                  # ВЫ добавляете prometheus-client (§1.2)

monitoring/
├── docker-compose.yml                # ВЫ расширяете сервисом `prometheus` (§2.2)
├── prometheus/
│   └── prometheus.yml                # ВЫ заполняете скелет (§2.3)
├── grafana/
│   └── dashboards/
│       └── lab08.json                # экспортируется из UI Grafana в задаче 3
└── docs/
    └── LAB08.md                      # ваш отчёт о сдаче
```

Обвязка из репозитория курса для этой лабораторной:
- `labs/lab8/prometheus/prometheus.yml` — **скелет** с маркерами ВАША ЗАДАЧА. Скопируйте его в `monitoring/prometheus/prometheus.yml` и заполните пропуски.

---

## Задача 1 — Инструментируйте Python-приложение (3 балла)

### 1.1 — Сначала читаем, потом пишем

Прочитайте это, прежде чем трогать `app.py` — это отвечает на вопросы, которые инструментация задаёт вам:
- [Prometheus metric types](https://prometheus.io/docs/concepts/metric_types/) — Counter / Gauge / Histogram / Summary
- [Instrumentation best practices](https://prometheus.io/docs/practices/instrumentation/) — правило «низкой кардинальности» и именование метрик
- [`prometheus_client` (Python)](https://github.com/prometheus/client_python) — Counter, Histogram, `generate_latest`, `CONTENT_TYPE_LATEST`

`ВАША ЗАДАЧА`: в `docs/LAB08.md` ответьте на эти три вопроса по 2–4 предложения каждый. Вы вернётесь и пересмотрите их после задачи 3:

1. Когда вы тянетесь к **Counter**, а когда к **Histogram**? Приведите по одному примеру каждого из *вашего собственного* приложения.
2. Почему вы запрашиваете `rate(counter[5m])`, а не сырое значение счётчика? (Подсказка: счётчики сбрасываются при перезапуске процесса.)
3. Что такое **кардинальность меток** и почему `user_id` или `request_id` в качестве метки в конечном итоге приведёт к OOM Prometheus?

### 1.2 — Добавьте клиентскую библиотеку

Добавьте точную фиксацию в `app_python/requirements.txt`:

```txt
prometheus-client==0.23.1
```

Пересоберите ваш образ из лабораторной 2, чтобы зависимость попала в контейнер.

### 1.3 — Определите метрики (`ВАША ЗАДАЧА`)

Вы добавите **две** метрики в `app_python/app.py`. Лекция (слайды 8, 10, 13) называет их, даёт метки и показывает набор bucket'ов по умолчанию из SRE. Ваша работа — объявить их, дать разумные **строки help** и выбрать правильный набор меток — только ограниченные перечисления.

`ВАША ЗАДАЧА`: объявите две метрики на уровне модуля:

| Переменная | Тип | Имя метрики | Метки | Замечания |
|---|---|---|---|---|
| `REQUESTS` | `Counter` | `app_requests_total` | `method`, `endpoint`, `status` | Считает каждый HTTP-запрос, на который отвечает ваш сервис |
| `LATENCY` | `Histogram` | `app_request_duration_seconds` | `method`, `endpoint` | Раскладывает длительность запроса по bucket'ам. Используйте значения по умолчанию из SRE: `(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)` |

```python
# app.py — добавьте в ваш сервис из лабораторной 1 (показан Flask; адаптируйте под middleware FastAPI)
import time
from flask import Flask, Response, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# --- Определения метрик (только метки низкой кардинальности!) ---
REQUESTS = Counter(
    ___,                # ВАША ЗАДАЧА: имя метрики — см. таблицу; оканчивается на _total по соглашению Prom
    ___,                # ВАША ЗАДАЧА: строка help — её читает любой, кто отлаживает ваши метрики
    ___,                # ВАША ЗАДАЧА: список меток — только ограниченные перечисления
)
LATENCY = Histogram(
    ___,                # ВАША ЗАДАЧА: имя метрики — суффикс _seconds — соглашение Prom для времени
    ___,                # ВАША ЗАДАЧА: строка help
    ___,                # ВАША ЗАДАЧА: список меток — уже, чем у счётчика (без status)
    buckets=___,        # ВАША ЗАДАЧА: кортеж по умолчанию из SRE из таблицы — bucket за вашим потолком SLO
)
```

> ⚠️ **Кардинальность — способ №1 уронить Prometheus в OOM.** Каждая уникальная комбинация меток — это свой временной ряд (~3–5 КБ RAM). Метки должны быть *ограниченными* перечислениями: `method` (~8), `endpoint` (десятки, нормализованные), `status` (~10). **Никогда** не кладите `user_id`, `request_id`, сырые пути, email или метки времени в метку. Тот же урок, что с Loki (лекция 7), тот же радиус поражения.

### 1.4 — Подключите хуки (`ВАША ЗАДАЧА`)

Flask даёт вам `before_request` (срабатывает до выполнения обработчика) и `after_request` (срабатывает после — получает объект `Response`). Паттерн — *запустить таймер в before, инкрементировать + наблюдать в after*. Тела пишете вы.

```python
@app.before_request
def _start_timer():
    request._t0 = ___                # ВАША ЗАДАЧА: захватите монотонное время старта
                                     #   — подсказка: time.perf_counter(), а НЕ time.time()

@app.after_request
def _record(response):
    duration = ___                   # ВАША ЗАДАЧА: now - request._t0
    if ___:                          # ВАША ЗАДАЧА: пропустить /metrics — исключите здесь его собственный путь
        return response              #            (иначе трафик скрейпинга отравляет ваши счётчики)
    endpoint = ___                   # ВАША ЗАДАЧА: используйте request.url_rule.rule при совпадении,
                                     #            откатитесь к "unknown", когда url_rule равен None
    REQUESTS.labels(___).inc()       # ВАША ЗАДАЧА: method, endpoint, str(response.status_code)
    LATENCY.labels(___).observe(___) # ВАША ЗАДАЧА: метки (method, endpoint) + длительность
    return response

@app.route("/metrics")
def metrics():
    return Response(
        ___,                         # ВАША ЗАДАЧА: байты из generate_latest()
        mimetype=___,                # ВАША ЗАДАЧА: CONTENT_TYPE_LATEST — неверный mimetype = молчаливый
                                     #            сбой парсинга на стороне Prometheus
    )
```

Подсказки — *не* полный код:
- **`request.url_rule.rule`** равен `"/health"` или `"/"` для совпавших маршрутов. Для 404 он равен `None` — откатитесь к `"unknown"`, чтобы кардинальность оставалась ограниченной.
- **Приведите статус** к `str(response.status_code)`. Значение метки должно быть строкой.
- **Эквивалент FastAPI**: одна корутина `@app.middleware("http")`, обрамляющая `await call_next(request)` с `time.perf_counter()`; экспонируйте `/metrics` через `Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)`.

### 1.5 — Проверьте локально

Вы можете проверить одним из двух способов — выберите один и будьте последовательны:

- **В стеке Compose лабораторной 7** (рекомендуется): пересоберите + перезапустите только сервис `app`, чтобы новый образ + `prometheus-client` работали на `localhost:8080`.
- **Автономный Python**: сначала `pip install -r requirements.txt` в venv, затем `python app.py`.

```bash
# Вариант A — через стек Compose (рекомендуется; совпадает с задачей 2 ниже).
# Запускайте из корня репозитория; стек слушает на хостовом порту 8080:
docker compose -f monitoring/docker-compose.yml up -d --build app    # подхватывает новый app.py + requirements

# Вариант B — автономный Python (запускайте из корня репозитория; порт лабораторной 1 по умолчанию 5000).
# Либо оставьте curl'ы ниже на :5000, либо задайте PORT=8080, чтобы совпасть с вариантом A:
# PORT=8080 python app_python/app.py

# Сгенерируйте трафик и посмотрите /metrics (вариант A → :8080; вариант B без изменений → :5000):
for i in $(seq 1 20); do curl -s localhost:8080/ > /dev/null; done
for i in $(seq 1 5);  do curl -s localhost:8080/health > /dev/null; done
curl -s localhost:8080/metrics | grep -E "^app_(requests_total|request_duration)"
```

Вывод — текстовый формат экспозиции Prometheus. **Иллюстративно — ваши счётчики будут другими:**

```
app_requests_total{endpoint="/",method="GET",status="200"} 20.0
app_requests_total{endpoint="/health",method="GET",status="200"} 5.0
app_request_duration_seconds_bucket{endpoint="/",method="GET",le="0.005"} 12.0
app_request_duration_seconds_bucket{endpoint="/",method="GET",le="0.01"}  18.0
app_request_duration_seconds_count{endpoint="/",method="GET"} 20.0
app_request_duration_seconds_sum{endpoint="/",method="GET"} 0.0421
```

**Проверка вменяемости:** выполните `curl -s localhost:8080/metrics > /tmp/m1.txt`, обратитесь к маршруту, `curl -s localhost:8080/metrics > /tmp/m2.txt`, сделайте diff. Итог должен **увеличиться ровно на 1** для маршрута, к которому вы обратились — и строка `endpoint="/metrics"` **не** должна существовать. Если `/metrics` считает сам себя, ваше исключение в §1.4 неверно.

### 1.6 — Доказательство работы

**Вставьте в `docs/LAB08.md`:**

- Полный вывод `curl -s localhost:8080/metrics | grep ^app_`, показывающий и строки `app_requests_total{...}`, и `app_request_duration_seconds_{bucket,sum,count}`, с вашими реальными счётчиками.
- Доказательство «без самосчёта»: `curl -s localhost:8080/metrics | grep -c 'endpoint="/metrics"'` возвращает `0`.
- Код определения метрик + хуков (фрагмент, не весь файл), закоммиченный в `app_python/app.py`.
- Ваши три письменных ответа из §1.1.

---

## Задача 2 — Разверните Prometheus и подключите скрейпинг (3 балла)

### 2.1 — Поймите модель pull

`ВАША ЗАДАЧА`: будьте готовы ответить на это в `docs/LAB08.md` §3 (напишите ответы сейчас, пересмотрите после §2.4):

1. Почему *неудачный скрейп* даёт вам здоровье цели «бесплатно» (`up == 0`), тогда как push-модель не может?
2. В чём разница между **job**, **target** и **scrape interval**?
3. В Docker Compose почему Prometheus должен скрейпить `app:8080` (имя сервиса), а **не** `localhost:8080`?

### 2.2 — Добавьте сервис Prometheus (`ВАША ЗАДАЧА`)

**Файл:** `monitoring/docker-compose.yml` (расширьте стек лабораторной 7 — не заменяйте его)

Prometheus присоединяется к той же сети `logging`, чтобы достигать Loki, Grafana и ваше `app` по имени сервиса. Образ + порты даны (чтобы версии были зафиксированы); тома, флаги команды, healthcheck и членство в сети — ваша работа.

```yaml
  # добавьте в monitoring/docker-compose.yml рядом с loki/alloy/grafana/app из лабораторной 7
  prometheus:
    image: prom/prometheus:v3.11.3
    command:
      - ___                              # ВАША ЗАДАЧА: путь --config.file= ВНУТРИ контейнера
                                         #   (куда вы смонтируете prometheus.yml ниже)
      - ___                              # ВАША ЗАДАЧА: --storage.tsdb.retention.time=
                                         #   (выберите значение — задача 4 документирует компромисс)
      - ___                              # ВАША ЗАДАЧА: --storage.tsdb.retention.size=
                                         #   (защита в глубину от заполнения диска)
    ports:
      - "9090:9090"
    volumes:
      - ___                              # ВАША ЗАДАЧА: bind-mount prometheus.yml :ro
      - ___                              # ВАША ЗАДАЧА: именованный том для /prometheus (TSDB)
    networks: [___]                      # ВАША ЗАДАЧА: какая сеть из лабораторной 7?
    healthcheck:
      test: ___                          # ВАША ЗАДАЧА: проверьте /-/healthy через wget --spider или curl --fail
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s

volumes:
  prometheus-data:                       # добавьте рядом с loki-data / grafana-data из лабораторной 7
```

Замечания — не пропускайте их, это *почему* за пропусками:

- **`--config.file=`** должен указывать туда, куда вы смонтировали `prometheus.yml` (обычно `/etc/prometheus/prometheus.yml`). Несовпадающие пути дают чистую строку «open ...: no such file» в `docker compose logs prometheus` при старте — сначала читайте логи, когда он не поднимается.
- **Ретенция — это флаг CLI Prometheus, а не настройка конфиг-файла** (это самый гуглимый подводный камень Prometheus 3.x). `retention.time` (например, `15d`) И `retention.size` (например, `2GB`) — что сработает первым, то и победит. Задокументируйте свой выбор в §4.
- **Том TSDB:** без персистентности каждый `docker compose down` стирает историю метрик. Смонтируйте именованный том в `/prometheus`, чтобы дашборды не пустели после перезапуска.
- **Сеть `logging`** — та, что из лабораторной 7. Размещение Prometheus в другой сети означает, что он не может разрешить `app` / `loki` / `grafana` — и вы будете отлаживать DNS вместо скрейпинга.

### 2.3 — Заполните конфиг скрейпинга (`ВАША ЗАДАЧА`)

**Файл:** `monitoring/prometheus/prometheus.yml`

Структура (один блок `global`, один список `scrape_configs`, один job на цель) — незыблема для Prometheus. Навык — **с какой частотой скрейпить**, **на каком hostname:port живёт каждая цель** и **как назвать каждый job** (потому что имя появляется в каждой метке дашборда и каждом алерте).

Начните со скелета:

```bash
cp labs/lab8/prometheus/prometheus.yml monitoring/prometheus/prometheus.yml
```

Что вы заполняете (в скелете те же пропуски):

```yaml
global:
  scrape_interval:        # ВАША ЗАДАЧА: как часто скрейпить
                          #   — вспомните лекцию §15: диапазоны запросов должны быть ≥ 4× этого
  evaluation_interval:    # ВАША ЗАДАЧА: как часто вычислять правила (совпадает со scrape_interval)

scrape_configs:
  - job_name:             # ВАША ЗАДАЧА: короткое имя в нижнем регистре, например "prometheus"
    static_configs:
      - targets:          # ВАША ЗАДАЧА: собственный /metrics Prometheus, ИЗНУТРИ контейнера
                          #   — это ЕДИНСТВЕННАЯ цель, использующая localhost

  - job_name:             # ВАША ЗАДАЧА: имя, по которому вы будете фильтровать позже — например up{job="..."}
    static_configs:
      - targets:          # ВАША ЗАДАЧА: имя сервиса Compose вашего приложения + порт
                          #   — НЕ localhost; Prometheus работает в другом контейнере

  - job_name:             # ВАША ЗАДАЧА
    static_configs:
      - targets:          # ВАША ЗАДАЧА: HTTP-порт Loki в сети logging

  - job_name:             # ВАША ЗАДАЧА
    static_configs:
      - targets:          # ВАША ЗАДАЧА: HTTP-порт Grafana в сети logging
```

Замечания:
- `metrics_path:` по умолчанию равен `/metrics`, поэтому его можно опустить.
- **Имена сервисов — это hostnames** в пользовательской сети Compose — `loki:3100`, `grafana:3000`, `app:8080`. Самоскрейпинг Prometheus — единственный, использующий `localhost`, потому что этот трафик остаётся внутри контейнера Prometheus.
- **Выбирайте `scrape_interval` осознанно.** Слишком короткий (1s) сжигает CPU и раздувает TSDB; слишком длинный (60s) делает графики процентилей рваными. Эталонная сдача использует `5s` для низкотрафиковой лабораторной; `15s` — продакшн-значение по умолчанию. Задокументируйте свой выбор в §3.

<details>
<summary>💡 Опциональная вторая цель — обвязка `echo` из курса</summary>

Репозиторий поставляет крошечный Go-сервис в `plumbing/echo` (вы встретите его снова в лабораторной 9), который уже экспонирует собственные метрики на `/metrics`. Его добавление даёт вашему дашборду второй инструментированный сервис — полезно, когда вы строите панели `sum by (job)`:

Добавьте сервис `echo` (`build: ../plumbing/echo`, порт `8081`, в сети `logging`) и пятый job скрейпинга, нацеленный на `echo:8081`. Тот же паттерн, новых концепций нет.

Не требуется для полных баллов; приятно для полировки дашборда в задаче 3.

</details>

### 2.4 — Поднимите и проверьте

```bash
cd monitoring
docker compose up -d
docker compose ps
```

Проверьте команды доказательства работы, которые вставите в §2.5:

```bash
# Prometheus поднят
curl -s localhost:9090/-/healthy           # ожидается: "Prometheus Server is Healthy."

# Цель каждого job — UP — это доказательство, что ваш конфиг скрейпинга + имена сервисов верны.
# Выполните это ПОСЛЕ того, как прошёл один scrape_interval.
curl -s localhost:9090/api/v1/targets \
  | jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"'
# (иллюстративно — каждая строка должна говорить "up"; если какая-то говорит "down", поле target этого job неверно)
# <your_app_job>: up                       # ВАША ЗАДАЧА: это главное утверждение —
# loki: up                                 #            строка для job_name, который вы выбрали в §2.3
# grafana: up                              #            для вашего приложения ДОЛЖНА говорить "up"
# prometheus: up
```

**Дерево решений по устранению неполадок:**
- Цель **down** → неверное имя сервиса, неверный порт или этот сервис не работает. `docker compose logs prometheus | grep -i scrape` показывает фактический URL, который пытался использовать Prometheus.
- **Цели вообще нет** для job → ошибка отступа YAML в `prometheus.yml`. `docker compose logs prometheus` показывает ошибку парсинга при старте.
- Цель **unknown** → подождите один `scrape_interval` и обновите; первый скрейп ещё не произошёл.

### 2.5 — Доказательство работы

**Вставьте в `docs/LAB08.md`:**

- `docker compose ps`, показывающий `prometheus` `Up` и `(healthy)` (последнее после истечения start_period).
- Точный вывод `curl -s localhost:9090/api/v1/targets | jq ...` из выше — каждая строка job должна говорить `up`, с явно присутствующим **`app: up`**. (Это главный критерий оценки задачи 2.)
- Скриншот `http://localhost:9090/targets`, подтверждающий то же (UI-версия выше).
- Ваши три письменных ответа из §2.1.

---

## Задача 3 — Дашборд RED в Grafana (2 балла)

### 3.1 — Добавьте Prometheus как источник данных

В Grafana из лабораторной 7:

1. **Connections → Data sources → Add data source → Prometheus**.
2. URL: `http://prometheus:9090` — имя сервиса в сети `logging`.
3. **Save & Test** → должно сообщить зелёным.

> Бонусный трек провижинит это автоматически; сделать это вручную один раз учит вас тому, что кодирует YAML провижининга.

### 3.2 — Напишите PromQL (`ВАША ЗАДАЧА`)

Это сердце лабораторной. Лекция (слайды 16, 18, 21) покрывает каждую нужную функцию; запросы пишете вы сами.

Для каждой строки напишите выражение PromQL, отвечающее на вопрос. Проверьте, выполнив его в **Explore** (источник данных Prometheus) против реального трафика — сначала сгенерируйте его:

```bash
for i in $(seq 1 200); do curl -s localhost:8080/ > /dev/null; curl -s localhost:8080/health > /dev/null; done
```

| Вопрос (RED) | Подсказка — одна именованная функция | Ограничение |
|---|---|---|
| **Q1 — Rate.** Запросы в секунду, в разрезе по эндпоинту. | `rate` | `sum by (endpoint) (...)` — оставить `endpoint`, отбросить остальное |
| **Q2 — Errors.** 5xx-запросы в секунду, по эндпоинту. | `rate` с матчером `status=~"5.."` | Та же форма, что Q1; матчер идёт **внутрь** селектора перед `rate` |
| **Q3 — Duration.** p95-задержка по эндпоинту. | `histogram_quantile` | `sum by (endpoint, le)` идёт **внутрь** `histogram_quantile`; никогда наоборот |
| **Q4 — Error ratio.** 5xx как *доля* от общего числа запросов. | Два `rate`, разделённые | Без группировки — одно число; умножьте на 100 для процентов, если хотите |

`ВАША ЗАДАЧА`: напишите все четыре запроса. Не копируйте из лекции дословно — сопоставьте их с *вашими* именами метрик из §1.3.

```promql
# Q1 — Rate (запросов/сек на эндпоинт)
___                              # ВАША ЗАДАЧА: rate(...) + sum by (endpoint)

# Q2 — Errors (5xx-запросов/сек на эндпоинт)
___                              # ВАША ЗАДАЧА: та же форма, селектор status=~"5.."

# Q3 — Duration (p95-задержка на эндпоинт)
___                              # ВАША ЗАДАЧА: histogram_quantile СНАРУЖИ sum by (endpoint, le)

# Q4 — Error ratio (доля 5xx от общего)
___                              # ВАША ЗАДАЧА: rate(5xx) / rate(total) — без группировки
```

Замечания (не пропускайте):

- **`rate()`** обрабатывает сбросы счётчиков (перезапуски процесса); `irate()` и сырое вычитание — **нет**. Для графиков держитесь `rate()`.
- **Нижняя граница диапазона:** при `scrape_interval: 5s` нижняя граница, которая не врёт — `rate(...[1m])`. При `15s` используйте `[5m]` или длиннее.
- **Никогда не усредняйте процентиль.** `histogram_quantile()` идёт *снаружи* `sum by (le, …)`, никогда внутри `avg()`. Попробуйте неправильную вложенность один раз и прочитайте ошибку Prometheus — это поучительно.
- **Используйте форму имён метрик из лекции**, если застряли на именовании (`http_requests_total` и т. п.) — но Q1–Q4 должны совпадать с именами метрик, которые вы фактически экспонировали в §1.3.

### 3.3 — Постройте дашборд — 6 панелей

Каждая панель отвечает на один вопрос. Запросы PromQL 1, 2, 3, 5, 6 описаны ниже; панель 4 (heatmap) — та, что вы пишете сами в расширении §3.2.

| # | Панель | Визуализация | Источник запроса | Отвечает на |
|---|-------|---------------|---|---|
| 1 | **Request rate** | Time series | Ваш Q1 | *Насколько загружено?* |
| 2 | **Error rate** | Time series | Ваш Q2 | *Как часто падает?* |
| 3 | **p95 latency** | Time series | Ваш Q3 | *Насколько медленно на 95-м процентиле?* |
| 4 | **Latency heatmap** | Heatmap | ВАША ЗАДАЧА — тот же ряд `_bucket`, но `sum by (le)` *без* `histogram_quantile` (панель heatmap сама вычисляет процентили) | *Как выглядит длинный хвост?* |
| 5 | **In-flight or total** | Gauge / Stat | `sum(rate(<your counter>[1m]))` | *Насколько загружено прямо сейчас?* |
| 6 | **Service uptime** | Stat | `up{job="<your app job name>"}` | *Мы живы?* |

`ВАША ЗАДАЧА`: напишите PromQL для панели 4 сами — это единственная, не покрытая Q1–Q4. Подсказка: heatmap **не** вызывает `histogram_quantile`; он визуализирует счётчики bucket'ов напрямую. Та же форма `sum by (le) (rate(...))`, без обёртки кванттиля.

**Как строить (Grafana 13):**
1. **Dashboards → New → New dashboard → Add visualization** → выберите источник данных **Prometheus**.
2. Вставьте PromQL; задайте тип визуализации из таблицы; озаглавьте каждую панель **по вопросу, на который она отвечает** («Ошибки в секунду по эндпоинту» лучше, чем «Запрос 2»).
3. Задайте разумные единицы: панель 1 = `req/s`; панель 3 = `seconds`; панели 2 = `req/s` с порогом, чтобы ненулевые ошибки делали панель красной.
4. Используйте `{{endpoint}}` (или `{{job}}`) в легенде, чтобы линии были подписаны, а не «Series 1».
5. **Save dashboard**, затем **Share → Export → Save to file**, закоммитьте в `monitoring/grafana/dashboards/lab08.json`.

> 💡 Хотите фору по панелям инфраструктуры? Импортируйте дашборд сообщества **ID 3662** (самостатистика Prometheus) через **Dashboards → New → Import** и привяжите его к вашему источнику данных Prometheus. Оценивается *ваш собственный* дашборд RED из 6 панелей.

### 3.4 — Доказательство работы

**Вставьте в `docs/LAB08.md`:**

- Скриншот дашборда из 6 панелей с **живыми данными на каждой панели** (сгенерируйте свежий трафик прямо перед скриншотом — пустые панели = без баллов).
- Запросы PromQL Q1–Q4 + запрос heatmap панели 4 в markdown-таблице, каждый с подписью вопроса, на который отвечает.
- Реальный ответ PromQL от вашего собственного трафика, захваченный через HTTP API (чтобы проверяющий видел *ваши* числа, а не только скриншот). Прогоните четыре запроса через `/api/v1/query` и захватите вывод:
  ```bash
  curl -s --get http://localhost:9090/api/v1/query \
       --data-urlencode 'query=___' \
       | jq '.data.result'
  # ВАША ЗАДАЧА: подставьте по очереди каждый из ваших запросов Q1–Q4; вставьте .data.result
  # (иллюстративно — ваши счётчики будут другими)
  # [{"metric":{"endpoint":"/"},"value":[1716894123.456,"127"]},
  #  {"metric":{"endpoint":"/health"},"value":[1716894123.456,"54"]}]
  ```
- Путь закоммиченного JSON-файла: `monitoring/grafana/dashboards/lab08.json`.

---

## Задача 4 — Готовность к проду (1 балл)

Укрепите стек, чтобы он не был игрушкой. Всё здесь строится на сервисе `prometheus`, который вы написали в §2.2 — пропуски уже там, эта задача — где вы *обосновываете* выбранные значения.

### 4.1 — Лимиты ресурсов

`ВАША ЗАДАЧА`: добавьте `deploy.resources` в сервис `prometheus`. Выберите разумные числа — RAM Prometheus масштабируется с числом активных рядов; для этой лабораторной пара сотен МиБ — щедро. Задокументируйте числа + обоснование в `LAB08.md`.

```yaml
    deploy:
      resources:
        limits:
          cpus: ___                 # ВАША ЗАДАЧА: потолок — сколько максимум вы бы позволили ему съесть?
          memory: ___               # ВАША ЗАДАЧА: потолок RAM — держите в уме число рядов
        reservations:
          cpus: ___                 # ВАША ЗАДАЧА: гарантированный минимум при планировании
          memory: ___               # ВАША ЗАДАЧА: гарантированный минимум памяти
```

### 4.2 — Ретенция

Вы заглушили флаги ретенции в §2.2. Задокументируйте **почему оба** `retention.time` И `retention.size` важны в `LAB08.md`: время — это ручка, определяемая SLA, размер — защита в глубину от разбушевавшейся кардинальности.

### 4.3 — Проверка состояния и персистентность

Блок healthcheck из §2.2 должен быть заполнен. Проверьте, что он работает:

```bash
docker compose ps                              # prometheus сообщает (healthy), как только истечёт start_period
docker compose down && docker compose up -d    # ПРИМЕЧАНИЕ: без `-v` — это стёрло бы именованные тома
sleep 30                                       # подождите первый скрейп после перезапуска (≥ один scrape_interval + start_period)
curl -s 'http://localhost:9090/api/v1/query?query=app_requests_total' | jq '.data.result | length'
# (иллюстративно — ненулевое значение означает, что том TSDB сохранил ряды через перезапуск;
#  ровно 0 означает, что том не был смонтирован или по ошибке использовался `down -v`)
```

### 4.4 — Доказательство работы

**Вставьте в `docs/LAB08.md`:**

- Вывод `docker compose ps`, показывающий **все** сервисы здоровыми, включая `prometheus (healthy)`.
- Вывод последовательности `down` → `up` → запрос выше, доказывающий, что история метрик пережила.
- Ваши значения лимитов ресурсов + обоснование одним предложением для каждого.

---

## Задача 5 — Документация (1 балл)

`ВАША ЗАДАЧА`: напишите `monitoring/docs/LAB08.md` со следующими разделами по порядку:

1. **Архитектура** — диаграмма Mermaid `app → Prometheus → Grafana` рядом с путём логов лабораторной 7 (чтобы одна и та же Grafana показывала оба столпа).
2. **Настройка** — как развернуть (`docker compose up -d`) и команды проверки из §2.4.
3. **Инструментация** — имена метрик + типы + метки, которые вы добавили, плюс ваши ответы из §1.1.
4. **Конфиг скрейпинга** — имена ваших job, ваш `scrape_interval`, модель pull (ответьте на вопросы §2.1).
5. **Дашборд** — таблица из §3.4: вопрос → PromQL → скриншот.
6. **Прод-конфиг** — обоснование ретенции, лимиты ресурсов, healthcheck, доказательство персистентности.
7. **Метрики против логов** — один абзац: когда вы тянетесь к Prometheus, а когда к запросу LogQL из лабораторной 7.
8. **Трудности и решения** — минимум одна настоящая (не «я был новичком в Prometheus»).

Включите фрагменты конфигурации (не целые файлы) и захваты из задач 1–4. Держите читаемым — это артефакт, который ваш будущий on-call «я» будет читать в 3 часа ночи.

---

## Бонусная задача — Автоматизация через Ansible (2 балла)

Расширьте роль `roles/monitoring` из лабораторных 6/7, чтобы один playbook разворачивал **логи + метрики** вместе.

`ВАША ЗАДАЧА`: обновите роль так, чтобы она:

- **Шаблонизировала** `prometheus/prometheus.yml` через Jinja2 — интервал скрейпинга, ретенция **и список целей** становятся переменными роли (определёнными в `defaults/main.yml`). Один и тот же шаблон рендерится правильно и для 4 целей, и для 14.
- **Расширила** шаблонизированный `docker-compose.yml` из лабораторной 7 сервисом `prometheus` + томом `prometheus-data`.
- **Провижинила** источник данных Prometheus в Grafana через `grafana/provisioning/datasources/`.
- **Провижинила** ваш экспортированный JSON дашборда RED через `grafana/provisioning/dashboards/`.
- **Дождалась** Prometheus `:9090/-/healthy` перед сообщением об успехе — тот же паттерн, что ожидание готовности в лабораторной 7, просто другой URL.
- Была **идемпотентной**: второй запуск сообщает `changed=0`.

Меньше подсказок, чем в задачах 1–5: имена переменных, структуру шаблона и опрос готовности придумайте сами. Бонус лабораторной 7 уже покрывал механику развёртывания `docker_compose_v2` + паттерн цикла готовности.

**Переменные, которые вам понадобятся как минимум** (не цитируйте-и-вставляйте — объявите в вашем `defaults/main.yml`):
- `prometheus_version` (например, `v3.11.3`), `prometheus_port` (`9090`)
- `prometheus_retention_time` (`15d`), `prometheus_retention_size` (`2GB`)
- `prometheus_scrape_interval` (`15s`)
- `prometheus_targets` — список dict'ов `{job, targets}`, чтобы Jinja2 `{% for %}` рендерил конфиг скрейпинга

**Доказательства (вставьте в `docs/LAB08.md`):**

- Вывод первого запуска (изменения > 0) и вывод второго запуска (`changed=0`).
- **Отрендеренный** (не шаблон) `prometheus.yml` из реального запуска.
- Скриншот Grafana, показывающий **оба** источника данных (Loki + Prometheus), работающих с трафиком.
- Путь: `ansible/roles/monitoring/` + `ansible/playbooks/deploy-monitoring.yml`.

---

## Как сдавать

```bash
git switch -c lab08
git add app_python/                                # инструментация + requirements
git add monitoring/                                # compose + prometheus.yml + дашборд
git add ansible/roles/monitoring \
        ansible/playbooks/deploy-monitoring.yml    # только если сделан бонус
git commit -m "feat(lab08): prometheus metrics + RED dashboard"
git push -u origin lab08
```

Откройте **два** PR:

- `your-fork:lab08` → `course-repo:master` *(на проверку)*
- `your-fork:lab08` → `your-fork:master` *(сливается в ваш собственный main)*

Чек-лист PR:

```text
- [ ] Задача 1 выполнена — Counter + Histogram + /metrics + хуки before/after; /metrics исключён из самосчёта
- [ ] Задача 2 выполнена — сервис prometheus в compose, prometheus.yml заполнен, все цели `up`
- [ ] Задача 3 выполнена — дашборд RED из 6 панелей, JSON закоммичен, реальный ответ PromQL захвачен
- [ ] Задача 4 выполнена — лимиты, ретенция, healthcheck здоров, персистентность доказана
- [ ] Задача 5 выполнена — LAB08.md со всеми 8 разделами + захваты
- [ ] Бонус выполнен — идемпотентная роль Ansible с ожиданием готовности, оба источника данных работают
```

---

## Критерии приёмки

### Задача 1 — Инструментация (3 балла)
- ✅ Объявлен Counter `app_requests_total` с метками `method, endpoint, status`
- ✅ Объявлен Histogram `app_request_duration_seconds` с метками `method, endpoint`, bucket'ы по умолчанию из SRE
- ✅ Хуки `before_request` / `after_request` наблюдают **каждый** запрос, кроме `/metrics`
- ✅ `/metrics` возвращает валидный текстовый формат Prometheus с правильным `Content-Type`
- ✅ `/metrics` **не** считает сам себя (`grep -c 'endpoint="/metrics"' = 0`)
- ✅ Три письменных ответа из §1.1 в `LAB08.md`

### Задача 2 — Скрейпинг Prometheus (3 балла)
- ✅ Сервис `prometheus` добавлен в сеть `logging` с флагами ретенции + healthcheck
- ✅ `prometheus.yml` имеет `global` + 4 job скрейпинга, заполненных из скелета
- ✅ `curl -s localhost:9090/api/v1/targets | jq` показывает **каждый** job `up`, с явно присутствующим `app: up`
- ✅ Три письменных ответа из §2.1 в `LAB08.md`

### Задача 3 — Дашборд RED (2 балла)
- ✅ 6 панелей с подходящими визуализациями; заголовки описывают вопрос, а не запрос
- ✅ Запросы PromQL Q1–Q4 + запрос heatmap панели 4 написаны студентом (не скопированы из лекции)
- ✅ Реальный ответ PromQL от собственного трафика студента захвачен через `/api/v1/query`
- ✅ JSON дашборда закоммичен в `monitoring/grafana/dashboards/lab08.json`

### Задача 4 — Прод-конфиг (1 балл)
- ✅ Лимиты ресурсов + reservations на `prometheus`
- ✅ Флаги ретенции (`time` и `size`) заданы в командной строке
- ✅ Healthcheck сообщает `(healthy)`; история метрик переживает `down`/`up`

### Задача 5 — Документация (1 балл)
- ✅ Все 8 разделов присутствуют в `monitoring/docs/LAB08.md`
- ✅ Ответы на исследования своими словами студента, а не цитаты из лекции

### Бонус — Ansible (2 балла)
- ✅ `prometheus.yml` шаблонизирован из переменной-списка `prometheus_targets`
- ✅ Источник данных + дашборд провижинятся (без кликов в UI Grafana)
- ✅ Развёртывание идемпотентно — второй запуск `changed=0`
- ✅ Ожидание готовности блокирует успех, пока Prometheus + Grafana не ответят
- ✅ Оба источника данных видны в Grafana

---

## Рубрика

| Задача | Баллы | Критерии |
|------|-------:|----------|
| **Задача 1** — Инструментация | **3** | Counter + Histogram объявлены правильно; хуки наблюдают запросы, кроме `/metrics`; валидный формат экспозиции |
| **Задача 2** — Скрейпинг Prometheus | **3** | Сервис в compose, конфиг скрейпинга заполнен, `/api/v1/targets` показывает `app: up` |
| **Задача 3** — Дашборд RED | **2** | 6 панелей с PromQL, написанным студентом; реальный ответ запроса захвачен; JSON закоммичен |
| **Задача 4** — Прод-конфиг | **1** | Лимиты, ретенция, healthcheck, персистентность |
| **Задача 5** — Документация | **1** | Все 8 разделов, захваты присутствуют, ответы своими словами студента |
| **Бонус** — Ansible | **2** | Идемпотентное шаблонизированное развёртывание полного стека логов+метрик |
| **Итого** | **12** | 10 основных + 2 бонусных |

---

## Ресурсы

<details>
<summary>📊 Prometheus</summary>

- [Prometheus overview](https://prometheus.io/docs/introduction/overview/)
- [Prometheus 3.0 announcement](https://prometheus.io/blog/2024/11/14/prometheus-3-0/) — UTF-8, нативные гистограммы, OTLP
- [Configuration reference](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [`scrape_config`](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config)
- [Metric types](https://prometheus.io/docs/concepts/metric_types/)
- [Native histograms](https://prometheus.io/docs/specs/native_histograms/)

</details>

<details>
<summary>🐍 Инструментация Python</summary>

- [`prometheus_client` (GitHub)](https://github.com/prometheus/client_python)
- [Python instrumentation guide](https://prometheus.io/docs/guides/python/)
- [Instrumentation best practices](https://prometheus.io/docs/practices/instrumentation/)
- [Metric naming](https://prometheus.io/docs/practices/naming/)

</details>

<details>
<summary>📈 PromQL и Grafana</summary>

- [PromQL basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [PromQL examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)
- [Grafana Prometheus data source](https://grafana.com/docs/grafana/latest/datasources/prometheus/)
- [Dashboard provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards)

</details>

<details>
<summary>📚 Методы наблюдаемости</summary>

- [RED method (Tom Wilkie, Grafana)](https://grafana.com/blog/the-red-method-how-to-instrument-your-services/)
- [USE method (Brendan Gregg)](https://www.brendangregg.com/usemethod.html)
- [The Four Golden Signals (Google SRE)](https://sre.google/sre-book/monitoring-distributed-systems/)

</details>

<details>
<summary>⚠️ Частые ловушки (из реальных dry-run)</summary>

- **Ловушка самосчёта `/metrics`.** Если ваш хук `after_request` записывает ответ на сам `/metrics`, каждый скрейп инкрементирует `app_requests_total{endpoint="/metrics",...}` — а при интервале скрейпинга 5 секунд это двенадцать фейковых «запросов в минуту», которые заглушают ваш реальный трафик. **Всегда** исключайте путь `/metrics` перед инкрементом; проверяйте, что `curl … | grep -c 'endpoint="/metrics"'` возвращает `0`. Это баг инструментации №1 — заметки эталонной сдачи явно проверяют его.
- **Кардинальность меток = OOM Prometheus.** Каждая уникальная комбинация меток — это временной ряд (~3–5 КБ RAM каждый). Помещение `user_id`, `request_id`, `trace_id`, сырых путей с ID (`/user/123`), email или меток времени в метку — самый быстрый способ уронить ingester. **Используйте `request.url_rule.rule`** для метки `endpoint` — `request.path` включает `/user/123` и `/user/456` как два различных ряда; правило `/user/<id>` схлопывает их. Тот же урок, что с метками Loki в лабораторной 7.
- **Путаница Counter и Gauge.** Счётчик только растёт (и сбрасывается в 0 при перезапуске процесса). Если вы обнаруживаете, что хотите `.dec()` или `.set()`, вы потянулись к счётчику, когда нужен gauge. И наоборот: запрос сырого значения счётчика даёт вам «запросы за всё время с момента загрузки» — почти никогда не то, что нужно. Всегда оборачивайте в `rate()` или `increase()`.
- **Выбор bucket'ов гистограммы.** Bucket'ы гистограммы `prometheus_client` по умолчанию заканчиваются на **10 секундах**. Если вы измеряете запросы к БД, которые могут занимать 30 с, каждый медленный запрос попадает в bucket `+Inf`, и ваш p99 — ложь. Раскладывайте гистограммы под *ожидаемый* диапазон с одним bucket'ом за потолком допуска — начните со значений по умолчанию SRE `(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10)` и подстраивайте по продовым данным. Слишком узкие bucket'ы на нижнем конце — симметричная ловушка: каждый быстрый запрос попадает в наименьший bucket, и вы не отличите 1 мс от 50 мкс.
- **DNS имён сервисов Compose.** Prometheus скрейпит цели по hostname через HTTP. Внутри сети Compose `logging` hostname — это **имя сервиса** (`app`, `loki`, `grafana`) — **не** `localhost` и **не** IP хоста. Единственная цель, законно находящаяся на `localhost`, — самоскрейпинг Prometheus (потому что этот трафик остаётся внутри контейнера Prometheus). Ошибётесь здесь — и `up{job="app"}` возвращает 0 без очевидной ошибки в UI; проверьте `docker compose logs prometheus | grep -i scrape`.
- **Ретенция — это флаг CLI, а не настройка конфиг-файла.** Это ловит каждого, кто мигрирует со статьи по 2.x. `retention_period` в `prometheus.yml` **игнорируется** — задавайте `--storage.tsdb.retention.time=15d` и `--storage.tsdb.retention.size=2GB` в списке `command:` вместо этого. Оба могут присутствовать; что сработает первым, то и победит.
- **Несовпадение `scrape_interval` с окном PromQL.** При `scrape_interval: 15s` `rate(...[15s])` вырожден (одна выборка или ноль), и график пуст. Минимальный диапазон запроса, дающий осмысленный вывод — `≥ 4× scrape_interval`. При скрейпах 5s → `[1m]` безопасно; при скрейпах 15s → `[5m]` — нижняя граница.
- **`histogram_quantile` снаружи, `sum by (le)` внутри — никогда наоборот.** Убийственный запрос процентиля: `histogram_quantile(0.95, sum by (endpoint, le) (rate(*_bucket[5m])))`. Оборачивание `histogram_quantile` *внутрь* агрегатора (например, `avg(histogram_quantile(...))`) — математическая бессмыслица — усреднение кванттилей не даёт кванттиль. Попробуйте один раз, прочитайте результат, усвойте.
- **`prometheus-client` >=0.23 выдаёт `# HELP`, `# TYPE` и `# UNIT`** — и Prometheus парсит все три. Если вы написали собственный ad-hoc текст `/metrics` вручную и пропустили строку `# TYPE`, Prometheus молча трактует каждый ряд как нетипизированный gauge, и `rate()` по нему возвращает NaN. Всегда используйте `generate_latest()`.

</details>

<details>
<summary>🛠️ Инструменты разработчика, которые стоит знать</summary>

- [`promtool`](https://prometheus.io/docs/prometheus/latest/command-line/promtool/) — поставляется в образе Prometheus; `promtool check config /etc/prometheus/prometheus.yml` валидирует перед перезагрузкой
- [`hey`](https://github.com/rakyll/hey) — генерирует ровный трафик к вашему приложению, чтобы наполнить дашборды (`hey -n 5000 -c 10 http://localhost:8080/`)
- [`jq`](https://jqlang.github.io/jq/) — для парсинга ответов `/api/v1/targets` и `/api/v1/query` в CLI

</details>

---

## Взгляд вперёд

| Лабораторная | Что добавляет к этому сервису |
|---:|---|
| 9 | k3d Kubernetes — разверните ваше инструментированное приложение + обвязочный сервис `echo` как Pod'ы, скрейпинг через sidecar |
| 10 | Чарт Helm 4 — упакуйте приложение + значения Prometheus |
| 12 | ConfigMaps + PVC — перемонтируйте конфиг Prometheus из ConfigMap; сохраните TSDB на PVC |
| 16 | Helm-чарт `kube-prometheus-stack` с CRD `ServiceMonitor`, автоматически обнаруживающими ваше приложение — тот же PromQL, нативная для K8s обвязка |

---

**Удачи!** 🚀

> **Помните:** счётчикам нужен `rate()`. Процентилям нужен `histogram_quantile()` *снаружи* `sum by (le)`. Метка никогда не должна быть уникальной для запроса или пользователя. **RED для каждого сервиса. USE для каждого ресурса.** И `/metrics` не должен считать сам себя.
