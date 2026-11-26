# Лабораторная работа 14 — Прогрессивная доставка с Argo Rollouts

![сложность](https://img.shields.io/badge/difficulty-intermediate-yellow)
![тема](https://img.shields.io/badge/topic-Progressive%20Delivery-blue)
![баллы](https://img.shields.io/badge/points-10%2B2-orange)
![технологии](https://img.shields.io/badge/tech-Argo%20Rollouts%201.8.4-informational)

> **Цель:** заменить `kind: Deployment` на `kind: Rollout`. Сами напишите список canary `steps:`, сами напишите манифесты `Service` для active + preview и (бонус) напишите PromQL за метрическим гейтом, который автоматически прерывает регрессирующий релиз.
> **Результат сдачи:** PR из ветки `lab14` с `k8s/lab10-app/templates/rollout.yaml`, двумя blue-green `Service`, необязательным `AnalysisTemplate` и `docs/LAB14.md`.

---

## Обзор

До лабораторной 9 вы выполняли rolling update с обычным `Deployment`: K8s заменяет pod'ы по 25% за раз и прекращает измерения в момент, когда readiness probe становится зелёным. Всплеск 5xx, который срабатывает лишь на 5% запросов, всё равно доставляется 100% пользователей. **Прогрессивная доставка** замыкает этот цикл: формируйте трафик шагами, ставьте за каждым шагом метрический гейт и позволяйте контроллеру откатываться без человека, смотрящего в Grafana в пятницу.

В этой лабораторной вы будете практиковать:
- CRD `Rollout` как замена `Deployment` — тот же pod template, новый блок `spec.strategy:`
- **Написание списка canary `steps:` с нуля** — каждый `setWeight` и каждый `pause` ваш
- **Написание манифестов `Service` active и preview с нуля** для blue-green
- **Написание запроса Prometheus и условий гейта** в `AnalysisTemplate` для бонуса
- Управление раскатками через `kubectl argo rollouts <verb>` — и изучение команд по именам

> ⚠️ **Область применения:** в основном пути нет интеграции с traffic-router — `setWeight` приближает по соотношению реплик (лекция 14, слайд 12). Один вариант с traffic-router есть в бонусе. Без mesh, без контроллера уведомлений. Держитесь ядра canary + blue-green и сами напишите каждую строку стратегии.

> 🪨 **Педагогическое ядро.** Главное доказательство этой лабораторной — один экран: `kubectl argo rollouts get rollout lab10-app-web`, показывающий **`Status: ॥ Paused`**, **`Message: CanaryPauseStep`** и **`SetWeight: 25, ActualWeight: 25`** на шаге 1/6, а затем, после выполнения `promote --full`, ту же команду на **шаге 6/6 `Healthy`**. `Rollout`, который сразу доходит до 100% без видимой паузы, не задействовал прогрессивную доставку. **Сохраните этот снимок.**

---

## Состояние проекта

**У вас должно быть из предыдущих лабораторных:**
- Кластер k3d на Kubernetes **1.36** (лабораторная 9)
- Helm-чарт в `k8s/lab10-app/` из лабораторной 10 — ваш шаблон `Deployment`, шаблон `Service`, `_helpers.tpl` и `values.yaml`
- ArgoCD **3.4**, управляющий этим чартом через `ApplicationSet` (лабораторная 13)
- Служебные сервисы `echo` и `health` из лабораторных 9 / 13 — `health` предоставляет `/metrics`, который вы используете в бонусе
- Экземпляр Prometheus из **лабораторной 8** (Docker-Compose) — см. раздел Подготовка о решении для in-cluster

**Эта лабораторная добавляет:**
- `k8s/lab10-app/templates/rollout.yaml` — **пишете вы** (задача 2: стратегия canary)
- `k8s/lab10-app/templates/service-active.yaml` — **пишете вы** (задача 3: blue-green active)
- `k8s/lab10-app/templates/service-preview.yaml` — **пишете вы** (задача 3: blue-green preview)
- `k8s/lab10-app/templates/analysistemplate.yaml` — **пишете вы** (бонус)
- `k8s/lab10-app/values-bluegreen.yaml` — переключатель для blue-green-потока (задача 3)
- `docs/LAB14.md` — ваш отчёт о сдаче

Служебные компоненты курса для этой лабораторной:
- `labs/lab14/prometheus-pointer.md` — что делать, если ваш Prometheus из лабораторной 8 всё ещё стек Docker-Compose вне кластера (бонусу нужен URL внутри кластера). **Не редактировать.**

К **лабораторной 16** вы замените bare in-cluster Prometheus на kube-prometheus-stack + `ServiceMonitor` — `AnalysisTemplate`, который вы пишете здесь, — это потребительский конец того конвейера.

---

## Подготовка

| Компонент | Версия | Примечания |
|---|---|---|
| Контроллер Argo Rollouts | **v1.8.4** | Выпущен 13 февраля 2026. НЕ используйте `latest` |
| Плагин `kubectl argo rollouts` | **v1.8.4** | Совпадает с контроллером |
| Kubernetes (k3s) | `v1.36.1-k3s1` | из лабораторной 9 |
| Helm | `v4.1.x` | из лабораторной 10 |
| Prometheus | `3.x` | экземпляр из лабораторной 8 — см. примечание об in-cluster ниже |

```bash
kubectl get nodes                  # 3-узловой кластер k3d из лабораторной 9 должен быть Running
helm version                       # 4.1.x из лабораторной 10
kubectl argo rollouts version      # ещё не установлен — это задача 1
```

> ⚠️ **Расположение Prometheus важно для бонуса.** В лабораторной 8 Prometheus работал в стеке Docker-Compose на вашем ноутбуке. `AnalysisTemplate`, работающий **внутри** кластера, не может достучаться до `http://localhost:9090` на вашем хосте. Три варианта, см. `labs/lab14/prometheus-pointer.md`:
>
> 1. **Указать на шлюз хоста** — k3d предоставляет `host.k3d.internal`; сегодня для бонуса работает, но лабораторная 16 всё равно заменит это на in-cluster стек.
> 2. **Запустить крошечный in-cluster Prometheus** в пространстве имён `monitoring` (указатель на манифест в `labs/lab14/`).
> 3. **Пропустить бонус.** Основным задачам 1–4 Prometheus не нужен.

Структура каталогов, которую вы создадите:

```
k8s/lab10-app/
├── templates/
│   ├── rollout.yaml                # пишете ВЫ — заменяет deployment.yaml (задача 2)
│   ├── service-active.yaml         # пишете ВЫ (задача 3)
│   ├── service-preview.yaml        # пишете ВЫ (задача 3)
│   └── analysistemplate.yaml       # пишете ВЫ (бонус)
├── values.yaml                     # добавьте переключатель `strategy.type`
└── values-bluegreen.yaml           # пишете ВЫ (задача 3) — переопределяет `strategy.type`
docs/
└── LAB14.md                        # ваш отчёт о сдаче
```

---

## Задача 1 — Основы Argo Rollouts (2 балла)

### 1.1 — Почему отдельный контроллер вместо Deployment

В `docs/LAB14.md` напишите по **3** предложения на каждую тему:

1. Какой сигнал `Deployment` на самом деле использует, чтобы решить, что раскатка успешна, и почему этого недостаточно, когда баг срабатывает на 5% запросов?
2. Как Argo Rollouts перераспределяет «трафик» без traffic-router (лекция 14, слайд 12), и каков предел точности при 5 репликах?
3. Какие **три** новых поля верхнего уровня добавляет CRD `Rollout`, которых нет у `Deployment`? (Подсказка: лекция 14, слайды 6–11 — `strategy.canary`, `strategy.blueGreen`, `analysis`/`backgroundAnalysis`.)

### 1.2 — Установите контроллер с фиксацией на v1.8.4

`ВАША ЗАДАЧА`: установите контроллер в пространство имён `argo-rollouts` из манифеста релиза **v1.8.4** — не `latest`, не `main`. Шаблон URL релиза: `https://github.com/argoproj/argo-rollouts/releases/download/<version>/install.yaml`.

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f ___        # ВАША ЗАДАЧА: URL install.yaml для v1.8.4
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=120s
```

> 💡 Причина, по которой `latest` запрещён: релиз, ломающий анализ `bluegreen` (в 1.8.0–1.8.3 был ровно этот баг — см. лекцию 14, слайд 21), незаметно прошёл бы через лабораторную ваших студентов. Фиксируйте версию, которую проверили ваши ассистенты (TA).

### 1.3 — Установите подходящий плагин kubectl

`ВАША ЗАДАЧА`: скачайте бинарник плагина **v1.8.4** для вашей ОС/архитектуры, сделайте его исполняемым и поместите в `PATH` под именем `kubectl-argo-rollouts`. Проверьте командой `kubectl argo rollouts version` — и клиент, и сервер должны сообщать `v1.8.4`.

```bash
# Пример для Linux amd64 — адаптируйте для darwin-arm64 / windows-amd64
curl -fSL -o kubectl-argo-rollouts ___       # ВАША ЗАДАЧА: URL бинарника плагина v1.8.4
chmod +x kubectl-argo-rollouts
sudo mv kubectl-argo-rollouts /usr/local/bin/

kubectl argo rollouts version                # ожидается: клиент v1.8.4 + сервер v1.8.4
```

> 💡 Плагин — **не** подкоманда `kubectl`, это отдельный бинарник, к которому `kubectl` обращается через shell. Если `kubectl argo rollouts version` говорит «unknown command», бинарника нет в вашем `PATH`.

### 1.4 — Установите dashboard (необязательно, но полезно)

`ВАША ЗАДАЧА`: примените манифест dashboard v1.8.4, сделайте port-forward на `localhost:3100` и сделайте скриншот пустого dashboard (вы наполните его, когда задача 2 создаст раскатку).

```bash
kubectl apply -n argo-rollouts -f ___        # ВАША ЗАДАЧА: URL dashboard-install.yaml для v1.8.4
kubectl argo rollouts ___                    # ВАША ЗАДАЧА: какая подкоманда открывает локальный UI на :3100?
                                             #            (одна из: dashboard, ui, serve, web)
```

### 1.5 — Подтверждение работы

**Вставьте в `docs/LAB14.md`:**

- 3 исследовательских ответа из §1.1
- `kubectl -n argo-rollouts get pods` — pod контроллера `Running`
- `kubectl argo rollouts version` — клиент и сервер оба `v1.8.4`
- Скриншот пустого dashboard по адресу `http://localhost:3100`

---

## Задача 2 — Canary-развёртывание (3 балла) ← **главная задача**

### 2.1 — Преобразуйте `Deployment` → `Rollout`

В вашем чарте из лабораторной 10 есть `templates/deployment.yaml`. **Переименуйте его** в `templates/rollout.yaml` и измените kind. Всё внутри `spec.template:` остаётся идентичным — те же метки, тот же контейнер, те же порты, те же probe. CRD Rollout переиспользует pod template вашего `Deployment` байт в байт. **Не меняйте селектор `Service`** — Argo Rollouts добавляет дополнительную метку `rollouts-pod-template-hash`, чтобы отличать stable-pod'ы от canary, но ваш существующий селектор (`app.kubernetes.io/name` + `instance`) по-прежнему совпадает с обоими.

`ВАША ЗАДАЧА`: напишите `templates/rollout.yaml`. Скелет ниже показывает части, **идентичные вашему Deployment** (чтобы вы не изобретали колесо), и **полностью оставляет пустым список canary `steps:`** — каждый шаг пишете вы.

```yaml
# k8s/lab10-app/templates/rollout.yaml
apiVersion: ___                                    # ВАША ЗАДАЧА: какой apiGroup/version владеет Rollout?
                                                   #            (подсказка: НЕ apps/v1 — см. лекцию 14, слайд 7)
kind: ___                                          # ВАША ЗАДАЧА
metadata:
  name: {{ include "lab10-app.fullname" . }}-web   # ТОТ ЖЕ суффикс -web, что у Deployment из лабораторной 10
                                                   # → рендерится как `lab10-app-web` при релизе по умолчанию;
                                                   # каждая CLI-команда ниже нацелена на это имя.
  labels:
    {{- include "lab10-app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}             # оставьте значение по умолчанию из лабораторной 10 — нужно ≥ 4 для видимых весов 25/50/75
  selector:
    matchLabels:
      {{- include "lab10-app.selectorLabels" . | nindent 6 }}
  template:
    # ⬇️ ИДЕНТИЧНО pod template вашего Deployment из лабораторной 13
    metadata:
      labels:
        {{- include "lab10-app.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          # ⬇️ тело pod template ИДЕНТИЧНО вашему Deployment из лабораторной 10 — скопируйте дословно
          # ⬇️ (ports, probes, resources, env). Здесь для краткости опущено.
          # См. ваш k8s/lab10-app/templates/deployment.yaml для тела, которое нужно вставить.
  strategy:
    canary:
      # ВАША ЗАДАЧА: напишите список из 7 шагов для canary 25 → 50 → 75 → 100
      # с РУЧНОЙ паузой между каждым изменением веса. Подсказки по формату ниже.
      #
      # Семантика шагов (лекция 14, слайд 7):
      #   - `- setWeight: ___`           сместить соотношение трафика/реплик до указанного процента
      #   - `- pause: {}`                ЖЁСТКИЙ ручной гейт — раскатка ждёт `promote`
      #   - `- pause: { duration: ___ }` пауза по времени (например, "30s", "2m") — раскатка продолжается сама
      #
      # Главное доказательство этой лабораторной — ПРИОСТАНОВЛЕННЫЙ canary на SetWeight 25 (в ссылках lab14
      # упоминается `CanaryPauseStep` на шаге 1/6). Поэтому шаг 1 должен смещать до 25%, а шаг 2 должен быть
      # РУЧНЫМ гейтом, а не паузой по времени — иначе раскатка никогда не просидит там достаточно
      # долго, чтобы снимок `kubectl argo rollouts get` показал `Paused`.
      #
      # Требуемая последовательность: 25 → pause → 50 → pause → 75 → pause → 100
      # (завершающим 100 пауза не нужна; на шаге 6/6 раскатка сама помечается Healthy)
      steps:
        - setWeight: ___                            # ВАША ЗАДАЧА
        - pause: ___                                # ВАША ЗАДАЧА: какая форма паузы? (см. подсказку выше)
        - setWeight: ___                            # ВАША ЗАДАЧА
        - pause: ___                                # ВАША ЗАДАЧА
        - setWeight: ___                            # ВАША ЗАДАЧА
        - pause: ___                                # ВАША ЗАДАЧА
        - setWeight: ___                            # ВАША ЗАДАЧА
```

**Почему важен каждый шаг:**
- **`setWeight: 25` на шаге 1** — именно это заставляет `ActualWeight: 25` появиться в `kubectl argo rollouts get`. Без этого ваш первый вес равен 100, и демонстрировать прогрессивную доставку нечего.
- **`pause: {}` (без duration)** висит, пока вы не выполните `promote`. Это гейт, за который реальная команда поставила бы проверку метрик.
- **`pause: { duration: 30s }`** — альтернатива, полезная для CI-демо, которые не могут ждать человека. Подходит любой вариант, но **как минимум шаг 2 должен быть `pause: {}`**, чтобы canary заметно постоял на 25% для снимка.
- **Завершающие 100 без паузы** — контроллер автоматически помечает раскатку `Healthy`; явный `setWeight: 100` в конце допустим, но лишний `- pause: {}` после него оставит раскатку зависшей.

### 2.2 — Запустите первую раскатку и зафиксируйте паузу

Примените чарт (через синхронизацию ArgoCD, если вы подключили ApplicationSet из лабораторной 13, иначе `helm upgrade`). Первое применение `Rollout` создаёт ресурс; контроллер помечает его `Healthy` на 100%, не проходя шаги (шаги выполняются только для **последующих** ревизий). Теперь поднимите образ, чтобы запустить настоящий canary:

```bash
helm upgrade lab10-app ./k8s/lab10-app --set image.tag=v2
# или закоммитьте values-dev.yaml с новым тегом и дайте ArgoCD синхронизировать его
```

Затем наблюдайте:

```bash
kubectl argo rollouts ___ rollout lab10-app-web --watch   # ВАША ЗАДАЧА: какой глагол показывает живой статус?
                                                       #            (один из: get, describe, status, list)
```

`ВАША ЗАДАЧА`: зафиксируйте момент, когда раскатка стоит на шаге 1/6 с `Message: CanaryPauseStep`, `SetWeight: 25`, `ActualWeight: 25`. Это главный артефакт лабораторной 14.

### 2.3 — Продвиньте раскатку через все гейты

```bash
kubectl argo rollouts ___ lab10-app-web --full            # ВАША ЗАДАЧА: какой глагол проходит ВСЕ оставшиеся паузы?
                                                       #            (full = пропустить ручные гейты И дождаться их)
```

Затем повторно зафиксируйте `kubectl argo rollouts get rollout lab10-app-web`, показывающий **шаг 6/6, `Status: ✔ Healthy`, `SetWeight: 100`**.

### 2.4 — Прервите раскатку на середине

`ВАША ЗАДАЧА`: запустите третью раскатку (поднимите тег до `v3`), дождитесь, пока она достигнет шага 1/6 с паузой на 25%, и затем прервите её. Убедитесь, что трафик вернулся к stable ReplicaSet, а раскатка сообщает `Degraded`.

```bash
helm upgrade lab10-app ./k8s/lab10-app --set image.tag=v3
# дождитесь шага с паузой на 25%:
kubectl argo rollouts get rollout lab10-app-web

kubectl argo rollouts ___ lab10-app-web                   # ВАША ЗАДАЧА: какой глагол отменяет выполняющуюся раскатку?
kubectl argo rollouts get rollout lab10-app-web           # ожидается: Status: ✖ Degraded, трафик на stable

# Теперь возобновите с шага 0, когда вы «исправили» образ (например, вернули тег на v2):
kubectl argo rollouts ___ rollout lab10-app-web           # ВАША ЗАДАЧА: какой глагол перезапускает Degraded-раскатку?
```

### 2.5 — Подтверждение работы

**Вставьте в `docs/LAB14.md`:**

- Содержимое блока `spec.strategy.canary` вашего `templates/rollout.yaml` (только список `steps:` — 8–10 строк)
- **Главный снимок** из §2.2 — `kubectl argo rollouts get rollout lab10-app-web`, показывающий `Paused`, `CanaryPauseStep`, `Step: 1/6`, `SetWeight: 25, ActualWeight: 25`
- Снимок **`promote --full`** из §2.3 — та же команда, теперь `Step: 6/6, Status: ✔ Healthy, SetWeight: 100`
- Снимки **abort + retry** из §2.4 — `Degraded` после прерывания, затем `Healthy` после `retry`
- 2–3 предложения о том, что вы наблюдали в dashboard во время окна паузы — была ли 1 из 4 реплик на новом ReplicaSet? (лекция 14, слайд 8)

---

## Задача 3 — Blue-green-развёртывание (3 балла)

### 3.1 — Зачем вторая стратегия

В `docs/LAB14.md` ответьте 2–3 предложениями:
- Какой канонический тип рабочей нагрузки для blue-green вместо canary? (Подсказка: лекция 14, слайд 5 — миграции схемы.)
- Во время окна переключения сколько копий ваших pod'ов работает? Почему это важно для стоимости кластера?

### 3.2 — Напишите два манифеста `Service` с нуля

Blue-green нужны **два** Service, указывающих на один и тот же набор меток pod'ов — Argo Rollouts переписывает их селекторы при продвижении, так что `activeService` всегда указывает на живой ReplicaSet, а `previewService` — на подготовленный. В вашем чарте из лабораторной 10 был **один** Service; теперь вы пишете **два**.

`ВАША ЗАДАЧА`: напишите `templates/service-active.yaml` и `templates/service-preview.yaml` с нуля. Они должны:

- Использовать helper `selectorLabels` чарта (чтобы контроллер раскатки мог изменять селектор)
- Различаться только `metadata.name` — один `<fullname>` (существующее имя, которое используют ваши вызывающие стороны), другой `<fullname>-preview`
- Оба предоставляют те же `port` / `targetPort`, что и ваш Service из лабораторной 10

(Скелета нет — к этому моменту вы написали ~6 манифестов Service в лабораторных 9, 10, 13. Если нужна форма API, `kubectl explain service.spec` — в одной shell-команде.)

> 💡 **Именование важно.** Имя `activeService` в вашем spec `Rollout` должно *точно* совпадать с существующим `Service`. Опечатка здесь приводит к ошибкам `Rollout` вроде `service "app-python-actv" not found` — и контроллер это не вылечит. Ссылайтесь на значение через `include "lab10-app.fullname" .` из того же helper, который использует ваш Service.

### 3.3 — Настройте стратегию blue-green

`ВАША ЗАДАЧА`: создайте `values-bluegreen.yaml`, который **переопределяет** блок `strategy:` вашего Rollout. Используйте один булев переключатель в `values.yaml` (например, по умолчанию `strategy.type: canary`; переопределите на `bluegreen` в новом файле) и ветку `{{- if eq .Values.strategy.type "bluegreen" }}` в `rollout.yaml`. **Не** поставляйте обе стратегии бок о бок — Argo Rollouts отвергает Rollout, объявляющий одновременно `canary` и `blueGreen`.

Ниже показана только внешняя форма blue-green; **четыре значения**, определяющие поведение переключения, оставлены пустыми.

```yaml
# в rollout.yaml, внутри spec:
  strategy:
    {{- if eq .Values.strategy.type "bluegreen" }}
    blueGreen:
      activeService: ___                # ВАША ЗАДАЧА: имя Service, куда идёт production-трафик
                                        #            (подсказка: совпадает с вашим <fullname>)
      previewService: ___               # ВАША ЗАДАЧА: имя Service, куда идут QA / smoke-тесты
                                        #            (подсказка: совпадает с <fullname>-preview)
      autoPromotionEnabled: ___         # ВАША ЗАДАЧА: true или false?
                                        #            (этой лабораторной нужен ручной promote — см. лекцию 14, слайд 9)
      scaleDownDelaySeconds: ___        # ВАША ЗАДАЧА: сколько секунд держать СТАРЫЙ ReplicaSet
                                        #            живым после продвижения, для мгновенного `undo`?
                                        #            (предложено: 300 = 5 минут — достаточно мало, чтобы не платить
                                        #             за два ReplicaSet весь день, и достаточно много, чтобы вы
                                        #             могли сделать `undo`, если заметите баг в первую минуту)
      # prePromotionAnalysis:           # необязательно — рассматривается в бонусе
    {{- else }}
    canary:
      steps:
        # ... ваш список шагов из задачи 2 ...
    {{- end }}
```

### 3.4 — Выполните blue-green-переключение

```bash
helm upgrade lab10-app ./k8s/lab10-app -f values-bluegreen.yaml --set image.tag=v1
# Убедитесь, что active Service отдаёт v1:
kubectl port-forward svc/lab10-app-web 8080:80 &
curl -s localhost:8080/ | jq .service

# Поднимите до v2 — контроллер поднимает новый ReplicaSet за PREVIEW Service:
helm upgrade lab10-app ./k8s/lab10-app -f values-bluegreen.yaml --set image.tag=v2

# В другом shell проверьте v2 через preview Service (prod всё ещё на v1):
kubectl port-forward svc/lab10-app-web-preview 8081:80 &
curl -s localhost:8081/ | jq .service       # ВАША ЗАДАЧА: подтвердите v2

# Убедитесь, что два Service СЕЙЧАС имеют РАЗНЫЕ pod IP в своих endpoints —
# это доказательство, что контроллер записал два разных селектора:
kubectl get endpoints lab10-app-web lab10-app-web-preview -o wide

# Продвиньте — active Service мгновенно переключается на v2 (новые pod'ы не планируются):
kubectl argo rollouts ___ lab10-app-web                  # ВАША ЗАДАЧА: тот же глагол, что и ручной гейт в задаче 2

# Проверьте мгновенный откат ДО истечения scaleDownDelaySeconds:
kubectl argo rollouts ___ lab10-app-web                  # ВАША ЗАДАЧА: какой глагол откатывает к предыдущему ReplicaSet?
kubectl get endpoints lab10-app-web                   # active вернулся к pod IP версии v1
```

### 3.5 — Подтверждение работы

**Вставьте в `docs/LAB14.md`:**

- Оба манифеста Service целиком (по одному на блок кода)
- Ваш блок `blueGreen:` со всеми четырьмя значениями + обоснование `scaleDownDelaySeconds` одним предложением
- **Два снимка `kubectl get endpoints`** из §3.4, показывающие `lab10-app-web` и `lab10-app-web-preview`, указывающие на **разные pod IP** в течение окна переключения — это главный blue-green-артефакт
- Снимки `promote` + `undo`, показывающие смену IP active Service
- 2 предложения, сравнивающие скорость blue-green `undo` и canary `abort` — что быстрее и почему

---

## Задача 4 — Документация (2 балла)

`ВАША ЗАДАЧА`: напишите `docs/LAB14.md` со следующими разделами по порядку:

1. **Подготовка** — снимки из задачи 1 (версии контроллера / плагина / dashboard, три отличия Rollout от Deployment)
2. **Стратегия canary** — ваш список `steps:`, снимки из §2.5 (Paused на 25% → Healthy на 6/6 → Degraded после прерывания → Healthy после retry) и абзац о том, что показывал dashboard во время окна паузы
3. **Стратегия blue-green** — ваши два манифеста Service, ваш блок `blueGreen:`, снимок разницы endpoint-IP, доказательства promote + undo
4. **Сравнение стратегий** — когда вы прибегаете к canary, а когда к blue-green? Ссылайтесь на таблицу со слайда 5 лекции 14; возьмите `app-python` (ваш сервис) и обоснуйте, какую стратегию вы бы использовали *в production* для типичного релиза функции и для миграции схемы
5. **Справочник CLI** — **пять глаголов**, которые вы запускали (`get`, `promote`, `abort`, `retry`, `undo` — плюс `version` и `dashboard`), по одному предложению на глагол о том, что он делает
6. **Трудности и выводы** — как минимум одна настоящая (сюрприз с селектором меток, слишком малый scaleDownDelay, неверный apiVersion, …) — см. Типичные ошибки

---

## Бонусная задача — Автоматическое прерывание по метрикам (2 балла)

**Цель:** добавить `AnalysisTemplate`, который опрашивает Prometheus и **автоматически прерывает** canary при регрессии метрики — без вмешательства человека.

Лекция (слайды 10–11) показала *форму* AnalysisTemplate. Вы пишете фактический запрос, условие успеха, лимит отказов и периодичность. Используйте метрики, которые вы инструментировали в **лабораторной 8** — `app_requests_total{status}` — канонический субстрат RED-метрики ошибок.

### Бонус.1 — Напишите AnalysisTemplate

`ВАША ЗАДАЧА`: напишите `k8s/lab10-app/templates/analysistemplate.yaml`. Kind и внешняя форма `spec.metrics:` даны; **запрос, условие успеха, лимит отказов и интервал** — ваши.

```yaml
# k8s/lab10-app/templates/analysistemplate.yaml
apiVersion: argoproj.io/v1alpha1
kind: ___                                          # ВАША ЗАДАЧА: какой kind? (подсказка: слайд 10)
metadata:
  name: success-rate
spec:
  args:
    - name: service-name
  metrics:
    - name: success-rate
      interval: ___                                # ВАША ЗАДАЧА: как часто делать выборку?
                                                   #   Правило со слайда 18: ≥ scrape_interval × 4
                                                   #   так что если Prometheus собирает каждые 15s, 60s — это минимум.
      count: ___                                   # ВАША ЗАДАЧА: сколько выборок перед объявлением успеха?
                                                   #   обычно 3–5 — меньше = дёргано, больше = медленные гейты.
      successCondition: ___                        # ВАША ЗАДАЧА: Go-выражение над `result` (слайд 10)
                                                   #   Вы вычисляете «долю не-5xx запросов».
                                                   #   Запрос ниже возвращает одно число с плавающей точкой в [0, 1].
                                                   #   Какой порог имеет смысл для доступности 99.x%?
                                                   #   (НЕ 0.95 — это антипаттерн со слайда 16.)
      failureLimit: ___                            # ВАША ЗАДАЧА: сколько неудачных выборок до АВТОПРЕРЫВАНИЯ?
                                                   #   0 = прервать при первом промахе (слишком дёргано)
                                                   #   2 = рекомендация из лекции
      provider:
        prometheus:
          address: ___                             # ВАША ЗАДАЧА: URL Prometheus внутри кластера
                                                   #   См. labs/lab14/prometheus-pointer.md для трёх вариантов.
                                                   #   Формат: http://<service-name>.<namespace>:9090
          query: |
            ___                                    # ВАША ЗАДАЧА: PromQL для
                                                   # метрики «доля не-5xx запросов» за 2-минутное окно.
                                                   #
                                                   # Используйте метрику из лабораторной 8: app_requests_total{status="..."}
                                                   # Форма такая:
                                                   #   sum(rate(<good>[2m])) / sum(rate(<all>[2m]))
                                                   # — см. слайд 10 для буквального шаблона.
                                                   #
                                                   # ВАЖНО: когда canary-pod только запустился, запросы
                                                   # ещё не попадали в него → числитель и знаменатель оба 0
                                                   # → Prometheus возвращает ПУСТОЙ ВЕКТОР → AnalysisTemplate
                                                   # падает на `result[0]` с NaN/index-out-of-range.
                                                   # Исправление: добавьте `or on() vector(0)`, чтобы пустой случай возвращал 0,
                                                   # а не ничего. (См. Типичные ошибки.)
                                                   #
                                                   # Аргумент `service-name` — ваш: используйте его,
                                                   # фильтруйте по `service="{{args.service-name}}"` или по метке
                                                   # `app.kubernetes.io/name`, которую несут ваши pod'ы `web`.
```

### Бонус.2 — Подключите его к canary

`ВАША ЗАДАЧА`: отредактируйте canary `steps:` из задачи 2 так, чтобы шаг `analysis` срабатывал после первого изменения веса, **и** добавьте анализ уровня spec, работающий непрерывно, чтобы регрессия посреди шага прерывала раскатку немедленно (а не только на следующем гейте).

```yaml
  strategy:
    canary:
      ___:                                         # ВАША ЗАДАЧА: какой ключ уровня spec запускает анализ НЕПРЕРЫВНО
                                                   #   (параллельно с шагами), чтобы регрессия посреди шага
                                                   #   прерывалась немедленно? (подсказка: лекция 14, слайд 11 «pro tip»)
        templates:
          - templateName: ___                      # ВАША ЗАДАЧА: какое имя AnalysisTemplate из Бонуса.1?
        args:
          - name: service-name
            value: ___                             # ВАША ЗАДАЧА: по какому имени сервиса фильтрует PromQL?
      steps:
        - setWeight: 25
        - ___:                                     # ВАША ЗАДАЧА: какой тип шага запускает анализ как ГЕЙТ
                                                   #   (т.е. блокируется до успеха/неудачи)?
            templates:
              - templateName: ___                  # ВАША ЗАДАЧА
            args:
              - name: service-name
                value: ___                         # ВАША ЗАДАЧА
        # … остаток ваших шагов из задачи 2 …
```

### Бонус.3 — Докажите автопрерывание

`ВАША ЗАДАЧА`: доставьте намеренно сломанный образ (например, добавьте обработчик `app.before_request`, который возвращает `500` в половине случаев) и запустите раскатку. Не трогая CLI, раскатка должна перейти в `Degraded` в течение `interval × failureLimit + count × interval` секунд. Зафиксируйте:

- `kubectl argo rollouts get rollout lab10-app-web`, показывающий `Degraded` с `Message: RolloutAborted` после сбоя анализа
- `kubectl get analysisruns -o wide`, показывающий неудачный `AnalysisRun` с `Phase: Failed` и неудачным `MeasurementCount`

### Бонус.4 — Пойдите дальше (требуется для полных 2 баллов) — выберите ОДИН

**Вариант A — Несколько AnalysisTemplate.** Напишите второй AnalysisTemplate (например, `p95-latency` с `histogram_quantile(0.95, ...)` по вашему Histogram из лабораторной 8), сошлитесь на **оба** шаблона в одном шаге `analysis:` и опишите, как взаимодействует `failureLimit`, когда падает *любой* из шаблонов. (Падение одного AnalysisTemplate прерывает раскатку — отказ объединяется по ИЛИ между шаблонами в рамках шага.)

**Вариант B — Несколько метрик в одном AnalysisTemplate.** Добавьте вторую запись в `spec.metrics:` (например, error-rate И p95 latency) внутри одного `AnalysisTemplate`. Argo Rollouts оценивает каждую независимо; раскатка прерывается, когда *любая* метрика превышает свой `failureLimit`. Опишите более чистую эргономику по сравнению с вариантом A.

### Бонус.5 — Подтверждение работы

**Вставьте в `docs/LAB14.md`:**

- Полный `AnalysisTemplate`, который вы написали — query, interval, count, successCondition, failureLimit, provider URL
- Снимки из §Бонус.3 (раскатка `Degraded` после сбоя анализа + `AnalysisRun`, показывающий измерения Prometheus, которые это вызвали)
- Ваше расширение из варианта A или B — второй шаблон ИЛИ вторая метрика, с файлом и зафиксированным вторым `AnalysisRun`
- 2–3 предложения о том, какое расширение вы выбрали и почему

---

## Как сдавать

```bash
git switch -c lab14
git add k8s/lab10-app/templates/rollout.yaml
git add k8s/lab10-app/templates/service-active.yaml k8s/lab10-app/templates/service-preview.yaml
git add k8s/lab10-app/values-bluegreen.yaml
git add k8s/lab10-app/templates/analysistemplate.yaml  # bonus only
git add docs/LAB14.md
git commit -m "feat(lab14): argo rollouts 1.8.4 — canary + blue-green + analysis"
git push -u origin lab14
```

Откройте **два** PR:

- `your-fork:lab14` → `course-repo:master` *(проверяется)*
- `your-fork:lab14` → `your-fork:master` *(сливается в ваш собственный main по завершении)*

Чек-лист PR:

```text
- [ ] Задача 1 — контроллер + плагин + dashboard зафиксированы на v1.8.4; ответы на исследование в LAB14.md
- [ ] Задача 2 — Rollout написан с нуля; canary 25→pause→50→pause→75→pause→100;
              снимок PAUSED-на-25% + снимок Healthy-на-6/6 + снимки abort/retry
- [ ] Задача 3 — два манифеста Service написаны с нуля; блок blueGreen со всеми четырьмя значениями;
              разница endpoints во время переключения; доказательства promote + undo
- [ ] Задача 4 — LAB14.md со всеми шестью разделами
- [ ] Бонус — AnalysisTemplate написан с нуля; автопрерывание продемонстрировано на сломанном образе;
              расширение из варианта A или B задокументировано
```

---

## Критерии приёмки

### Задача 1 — Основы (2 балла)
- ✅ Контроллер, плагин и dashboard **все v1.8.4** (не `latest`)
- ✅ `kubectl argo rollouts version` показывает клиент и сервер оба `v1.8.4`
- ✅ Три отличия Rollout от Deployment задокументированы в LAB14.md

### Задача 2 — Canary (3 балла)
- ✅ `templates/rollout.yaml` написан с нуля — `apiVersion`, `kind`, полный список `spec.strategy.canary.steps:` заполнен
- ✅ Список шагов — `25 → pause → 50 → pause → 75 → pause → 100` — **пауза после 25 должна быть `pause: {}` (ручная)**
- ✅ **Главный снимок**: `kubectl argo rollouts get rollout lab10-app-web`, показывающий `Status: ॥ Paused`, `Message: CanaryPauseStep`, `Step: 1/6`, `SetWeight: 25, ActualWeight: 25`
- ✅ **Снимок продвижения**: та же команда после `promote --full`, показывающая `Status: ✔ Healthy`, `Step: 6/6`, `SetWeight: 100`
- ✅ Abort + retry продемонстрированы — снимки показывают `Degraded`, затем снова `Healthy`

### Задача 3 — Blue-Green (3 балла)
- ✅ `templates/service-active.yaml` и `templates/service-preview.yaml` **написаны с нуля** — в этой лабораторной скелет не даётся
- ✅ Блок `blueGreen:` со всеми четырьмя заполненными значениями (`activeService`, `previewService`, `autoPromotionEnabled`, `scaleDownDelaySeconds`)
- ✅ **Снимок разницы endpoints**: `kubectl get endpoints lab10-app-web lab10-app-web-preview` показывает **разные pod IP** в течение окна переключения
- ✅ Promote + undo продемонстрированы — `kubectl get endpoints lab10-app-web` показывает, как active-селектор возвращается обратно

### Задача 4 — Документация (2 балла)
- ✅ Все шесть разделов присутствуют в `docs/LAB14.md`
- ✅ Раздел справочника CLI называет пять глаголов (`get`, `promote`, `abort`, `retry`, `undo`) с предложением на каждый
- ✅ Задокументирована одна настоящая трудность (не «я раньше никогда не видел YAML»)

### Бонус — Автоматическое прерывание по метрикам (2 балла)
- ✅ `AnalysisTemplate` написан с нуля — query, condition, interval, count, failureLimit все ваши
- ✅ Запрос использует метрику `app_requests_total` из лабораторной 8 с защитой `or on() vector(0)`
- ✅ Автопрерывание продемонстрировано на намеренно сломанном образе — снимки показывают `Degraded` с `RolloutAborted` из-за сбоя анализа (без ручного `abort`)
- ✅ Расширение из варианта A или B реализовано — второй шаблон ИЛИ вторая метрика, со своим доказательством `AnalysisRun`

---

## Рубрика

| Задача | Баллы | Критерии |
|------|-------:|----------|
| **Задача 1** — Основы | **2** | Контроллер v1.8.4 + плагин + dashboard; отличия Rollout от Deployment |
| **Задача 2** — Canary | **3** | Написанные вручную шаги; главный снимок paused-на-25%; promote-до-Healthy; abort + retry |
| **Задача 3** — Blue-Green | **3** | Написанные вручную Service; блок `blueGreen:` с четырьмя значениями; endpoint IP различаются во время переключения; мгновенный `undo` |
| **Задача 4** — Документация | **2** | Шесть разделов, объяснение CLI-глаголов, настоящая трудность |
| **Бонус** — Автопрерывание | **2** | Написанный вручную AnalysisTemplate + PromQL из лабораторной 8; автопрерывание на сломанном образе; расширение из варианта A или B |
| **Итого** | **12** | 10 основных + 2 бонусных |

**Оценивание:**
- **10/10:** обе стратегии end-to-end, главный снимок paused-at-25% однозначен, документация честная
- **8–9/10:** обе работают, незначительные пробелы в доказательствах (например, отсутствует blue-green разница endpoints)
- **6–7/10:** canary работает, но blue-green Service не написаны с нуля, ИЛИ отсутствует разница endpoint-IP
- **<6/10:** список шагов скопирован из документации без главной темы 25→pause, ИЛИ Service не написаны

---

## Ресурсы

<details>
<summary>📚 Документация Argo Rollouts</summary>

- [Документация Argo Rollouts](https://argoproj.github.io/argo-rollouts/) — начните с *Features*
- [Спецификация Rollout](https://argoproj.github.io/argo-rollouts/features/specification/) — каждое поле в CRD
- [Стратегия canary](https://argoproj.github.io/argo-rollouts/features/canary/)
- [Стратегия blue-green](https://argoproj.github.io/argo-rollouts/features/bluegreen/)
- [Анализ и прогрессивная доставка](https://argoproj.github.io/argo-rollouts/features/analysis/)
- [`kubectl argo rollouts` CLI](https://argoproj.github.io/argo-rollouts/generated/kubectl-argo-rollouts/kubectl-argo-rollouts/) — каждая подкоманда
- [Релиз Argo Rollouts v1.8.4](https://github.com/argoproj/argo-rollouts/releases/tag/v1.8.4) — фиксируйте именно этот тег

</details>

<details>
<summary>📦 Служебные компоненты курса</summary>

- `labs/lab14/prometheus-pointer.md` — три способа дать in-cluster AnalysisTemplate доступный URL Prometheus
- `plumbing/health/README.md` — эндпоинт `/metrics`, на который вы также можете нацелить бонусный запрос

</details>

<details>
<summary>⚠️ Типичные ошибки (из реальных прогонов)</summary>

- **`kubectl rollout restart deployment/lab10-app-web` НЕ работает с Rollout.** Основные подкоманды `kubectl rollout` нацелены на `Deployment` / `DaemonSet` / `StatefulSet`. CRD `Rollout` принадлежит Argo Rollouts, а не K8s rollout API. Используйте вместо этого `kubectl argo rollouts restart lab10-app-web` — тот же глагол, другой бинарник. Симптом: `error: deployments.apps "lab10-app-web" not found`, хотя `kubectl get rollouts` его показывает.

- **AnalysisTemplate падает на `result[0]` с NaN, когда нет трафика.** Когда canary-pod только запустился, запросы в него не попадали → `sum(rate(app_requests_total{...}[2m]))` возвращает **пустой вектор**, а не 0. Выражение `successCondition` `result[0] >= 0.99` тогда выдаёт ошибку, и AnalysisRun показывает `Inconclusive` или `Error` вместо вычисления. Исправление: добавьте `or on() vector(0)` к PromQL — тогда Prometheus вернёт `0` для пустого случая и выражение вычислится корректно. Это самый частый провал бонусной задачи.

- **`scaleDownDelaySeconds` — это ловушка на случай «трафик всё ещё на preview».** Слишком высокое значение (например, `3600`) означает, что каждое blue-green-переключение оставляет **старый** ReplicaSet живым на час — сжигая вычисления и запутывая всех, кто видит устаревшие pod'ы. Слишком низкое (например, `30`) означает, что к моменту, когда вы заметите баг v2 в production, ReplicaSet v1 уже не останется для `undo`. 300 секунд (5 минут) — разумное значение по умолчанию; опишите свой выбор.

- **`kubectl set image` требует плагин, а не основной kubectl.** `kubectl set image rollout/lab10-app-web web=ghcr.io/...:v2` выдаёт ошибку `the server doesn't have a resource type "rollout"`. Используйте вместо этого `kubectl argo rollouts set image lab10-app-web web=ghcr.io/...:v2`. Или — лучшая практика — проводите изменения образа через Helm / GitOps и дайте ArgoCD синхронизировать, чтобы изменение было в Git.

- **Prometheus не в кластере → AnalysisTemplate до него не достаёт.** Prometheus из лабораторной 8 работает в стеке Docker-Compose на вашем ноутбуке. Изнутри k3d `http://localhost:9090` резолвится в localhost **pod'а**, а не вашего хоста. Три решения описаны в `labs/lab14/prometheus-pointer.md`: (а) `host.k3d.internal:9090` изнутри k3d (сегодня работает, сломается в лабораторной 16, когда вы двинетесь дальше); (б) развернуть минимальный Prometheus в пространство имён `monitoring` кластера; (в) дождаться kube-prometheus-stack из лабораторной 16 и пропустить бонус до тех пор.

- **Загрязнение селектора из-за чарта лабораторной 13.** Argo Rollouts добавляет `rollouts-pod-template-hash` к меткам pod'ов, чтобы отличать stable от canary. Если ваш helper `selectorLabels` из лабораторной 10 включает что-то помимо `name` + `instance` (например, `version` — это антипаттерн из лекции 15), мутация контроллера конфликтует с вашим helper, и Service в итоге выбирает *оба* ReplicaSet. Держите `selectorLabels` на минимуме из двух ключей (это то же правило, что в helper'ах лабораторной 10).

- **Продвижение ручного гейта до того, как canary действительно на паузе.** `kubectl argo rollouts promote lab10-app-web` возвращается сразу, если нет активной паузы — он **не** ждёт следующего шага. Если запустить его слишком рано в скрипте, раскатка пропустит ваш главный момент для снимка и сразу дойдёт до 100%. Дождитесь, пока `kubectl argo rollouts get` покажет `Paused / CanaryPauseStep`, прежде чем продвигать.

- **`autoPromotionEnabled: true` в blue-green незаметно пропускает ручной гейт.** По умолчанию `false`, но многие туториалы показывают `true` для CI-демо. При `true` новый ReplicaSet продвигается, как только становится Ready — ваше окно валидации через preview-Service равно **нулю секунд**. Всегда ставьте `false` в values вашей лабораторной; `true` — только в полностью автоматизированных конвейерах с prePromotionAnalysis.

- **`apiVersion: apps/v1` в Rollout.** Срабатывает мышечная память от `Deployment` — Rollout живёт в `argoproj.io/v1alpha1`, а не `apps/v1`. `kubectl apply` возвращает `no matches for kind "Rollout" in version "apps/v1"`, и файл незаметно не применяется, если вы используете `helm template | kubectl apply -f -`. Всегда перепроверяйте первые две строки.

</details>

<details>
<summary>🛠️ Инструменты, которые стоит знать</summary>

- `alias kr='kubectl argo rollouts'` — экономит вам 18 символов в каждой команде
- [`argo-rollouts/dashboard`](http://localhost:3100) — локальный UI — самый чистый способ сделать скриншоты для задач 2 / 3
- [`kubectl get analysisruns -A`](https://argoproj.github.io/argo-rollouts/features/analysis/) — каждый запуск анализа, который когда-либо создавал контроллер, включая неудачные, из-за которых раскатка прервалась

</details>

---

## Взгляд вперёд

| Лабораторная | Что она добавляет этому стеку |
|---:|---|
| 15 | StatefulSet'ы — stateful-нагрузки не вписываются в модель Rollout; вместо этого упорядоченная идентичность pod'ов + PVC на каждый pod |
| 16 | **kube-prometheus-stack** + CRD `ServiceMonitor` — заменяет ваш самодельный URL Prometheus полноценным in-cluster стеком мониторинга; ваш `AnalysisTemplate` из этой лабораторной продолжает работать, только с `address: http://prometheus-operated.monitoring:9090` |

---

**Удачи!** 🚦

> **Помните:** `Rollout` — это `Deployment` плюс стратегия. Без метрических гейтов вы лишь замедлили плохое развёртывание; с ними вы автоматизировали откат. Главная тема этой лабораторной — `SetWeight: 25, ActualWeight: 25, Message: CanaryPauseStep` — это момент, когда «развёрнуто» перестаёт означать «выпущено» и начинает означать «выпущено, *если canary переживёт гейт*».
