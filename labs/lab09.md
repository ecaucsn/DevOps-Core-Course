# Лабораторная работа 9 — Основы Kubernetes на k3d

![difficulty](https://img.shields.io/badge/difficulty-intermediate-yellow)
![topic](https://img.shields.io/badge/topic-Kubernetes-blue)
![points](https://img.shields.io/badge/points-10%2B2-orange)
![tech](https://img.shields.io/badge/tech-Kubernetes%201.36%20%7C%20k3d-informational)

> **Цель:** поднять локальный кластер k3d (1 server + 2 agents), развернуть **два** сервиса рядом — ваш образ Python из лабораторной 2 и Go-сервис `echo` из курса — и доказать, что они могут общаться друг с другом через `Service` + kube-DNS.
> **Результат сдачи:** PR из ветки `lab09`, добавляющий `k8s/` (манифесты Deployment + Service для обоих сервисов + бонусный Ingress) и `k8s/docs/LAB09.md` со скриншотами-доказательствами.

---

## Обзор

В этой лабораторной работе вы отработаете:
- Управление кластером через `kubectl get / describe / logs / exec / apply / rollout`
- **Написание манифестов Deployment + Service от самого API** — выбор правильных `apiVersion/kind`, корректный «треугольник» label/selector, подбор requests/limits, настройку проб на дешёвом эндпоинте
- Понимание сетевой модели K8s: виртуальный IP `Service` → короткое имя kube-DNS → список эндпоинтов → IP pod'ов
- Импорт локально собранных образов в containerd кластера k3d
- Масштабирование, раскатку и откат `Deployment`

> ⚠️ **Область:** только чистый YAML — Helm будет в лабораторной 10. Никаких постоянных томов, секретов, сбора метрик — это придёт в лабораторных 11, 12, 16. Не тянитесь к `kubectl edit` и ничего не шаблонизируйте; сначала изучите голый API.

> 🪨 **Педагогическая суть.** До лабораторной 8 вы запускали **один** сервис. С одним сервисом вопрос «зачем стабильный IP и DNS-имя?» по-настоящему трудно ответить. Эта лабораторная запускает **два**. Изнутри вашего pod'а `web` вы выполните `curl http://echo/ping` и получите в ответ `pong` — этот единственный round-trip задействует kube-DNS, label selectors и балансировку нагрузки Service сразу. **Если вы сохраните только один скриншот, сохраните именно этот.**

---

## Состояние проекта

**У вас должно быть из предыдущих лабораторных:**
- `app_python/` из лабораторной 1 — сервис Flask/FastAPI с `/` и `/health`
- Рабочий образ контейнера из него из лабораторной 2 (запушенный в GHCR / Docker Hub, **или** собранный локально и помеченный тегом)
- Знакомство с `docker compose up` (лабораторные 6–8) — вы прочувствовали его пределы

**Эта лабораторная добавляет:**
- `k8s/web-deployment.yaml` — **пишете вы** (Deployment для вашего образа из лабораторной 2)
- `k8s/web-service.yaml` — **пишете вы** (Service перед `web`)
- `k8s/echo-deployment.yaml` — **пишете вы** (Deployment для сервиса `echo` из курса)
- `k8s/echo-service.yaml` — **пишете вы** (ClusterIP Service для `echo`)
- `k8s/ingress.yaml` — **пишете вы** (Traefik Ingress, только бонус)
- `k8s/docs/LAB09.md` — ваш отчёт о сдаче

К лабораторной 10 вы упакуете всё это заново как единый чарт **Helm 4**; к лабораторной 13 ArgoCD развернёт их через `ApplicationSet`. Поэтому сделайте labels/selectors правильно *сейчас* — они распространяются повсюду.

Инфраструктура репозитория курса для этой лабораторной:
- `plumbing/echo/` — Go HTTP-сервис, который вы развернёте в задаче 3. **Не изменяйте.** Предсобранный образ публикуется CI курса в `ghcr.io/inno-devops-labs/echo:v1`. Список эндпоинтов см. в `plumbing/echo/README.md`.

---

## Настройка

Версии, используемые в этой лабораторной — зафиксируйте их там, где у вас есть выбор:

| Компонент | Версия | Выпущено |
|---|---|---|
| Kubernetes (k3s) | `v1.36.1-k3s1` | 22 апреля 2026 (1.36 "Haru") |
| k3d | 5.7+ | — |
| kubectl | 1.36.x (в соответствии с кластером) | — |
| образ `echo` | `ghcr.io/inno-devops-labs/echo:v1` | публикуется CI курса |

```bash
docker --version           # 28.x or 29.x — k3d runs k3s inside Docker
k3d version                # 5.7+
kubectl version --client   # 1.36.x — match the cluster you'll create
```

> ⚠️ **Не используйте Kubernetes, встроенный в Docker Desktop.** Он отстаёт от upstream, и посреди лабораторной вы столкнётесь с сюрпризами из-за рассинхронизации версий.

Создайте структуру каталогов (файлы вы заполните сами):

```
k8s/
├── web-deployment.yaml          # YOU write this (§2)
├── web-service.yaml             # YOU write this (§2)
├── echo-deployment.yaml         # YOU write this (§3)
├── echo-service.yaml            # YOU write this (§3)
├── ingress.yaml                 # YOU write this (bonus only)
└── docs/
    └── LAB09.md                 # your submission report
```

---

## Задача 1 — Локальный кластер k3d (2 балла)

### 1.1 — Почему k3d, а не minikube / kind / Docker Desktop

В `docs/LAB09.md` ответьте в 2–3 предложениях на каждый:

1. Что на самом деле запускает k3d внутри Docker, и чем это отличается от подхода minikube на основе VM?
2. Почему этой лабораторной нужен **многоузловой** кластер (`--agents 2`)? Что видно на 3 узлах, чего не видно на 1?
3. Какой ingress-контроллер и какую реализацию LoadBalancer k3d поставляет по умолчанию, и что изменилось бы в вашем бонусном Ingress, если бы вы заменили k3d на kind?

(Слайд 13 лекции 9 + [документация k3d](https://k3d.io/) покрывают это.)

### 1.2 — Создайте кластер

`ВАША ЗАДАЧА`: поднимите кластер с именем `devops` с **1 server + 2 agents** на Kubernetes **1.36.1**, смапив порты LoadBalancer `80→8080` и `443→8443` на вашем хосте, чтобы бонусный Ingress был доступен.

```bash
# YOUR TASK lines below:
#   --image:  which k3s tag = K8s 1.36.1?  (see hint after the block)
#   --agents: how many agents for a multi-node cluster?
#   first -p: host port that maps cluster :80
#   second -p: host port that maps cluster :443
k3d cluster create devops \
  --image rancher/k3s:___-k3s1 \
  --agents ___ \
  -p "___:80@loadbalancer" \
  -p "___:443@loadbalancer"
```

> 💡 Теги образов k3s **дописывают** `-k3s1` к версии K8s из upstream. Выберите самый новый тег `v1.36.x-k3s1` из [`rancher/k3s` на Docker Hub](https://hub.docker.com/r/rancher/k3s/tags).

### 1.3 — Проверьте

```bash
kubectl config use-context k3d-devops    # k3d sets this automatically — sanity-check
kubectl version                          # server MUST report 1.36.x; client can be ±1 minor (skew is OK)
kubectl cluster-info
kubectl get nodes -o wide                # YOUR TASK: expect exactly THREE nodes — 1 server + 2 agents
```

> 💡 Если `kubectl` выводит `WARNING: version difference between client (1.34) and server (1.36) exceeds the supported version skew`, это предупреждение, а не ошибка — лабораторная всё равно засчитывается. Чтобы его заглушить, установите kubectl 1.36.x в соответствии с кластером.

### 1.4 — Подтверждение работы

**Вставьте в `docs/LAB09.md`:**

- Ответы на 3 исследовательских вопроса из §1.1
- `kubectl version`, показывающий client + server `1.36.x`
- `kubectl get nodes -o wide`, показывающий **3** узла, все `Ready`, все `v1.36.1+k3s1`
- Вашу команду `k3d cluster create` (чтобы проверяющий мог воссоздать ваше окружение)

---

## Задача 2 — Разверните ваш сервис `web` (3 балла)

Это навык написания манифестов. Форма ниже показывает, какие поля требует `Deployment`; **значения** выводите сами из API K8s + вашей работы в лабораторных 1/2.

### 2.1 — Deployment

`ВАША ЗАДАЧА`: напишите `k8s/web-deployment.yaml`. Три набора labels-and-selectors должны согласовываться по всему файлу (metadata Deployment, `spec.selector.matchLabels` и `spec.template.metadata.labels`) — этот треугольник label и есть ошибка №1 в YAML для K8s. Service в §2.2 будет выбирать тот же label.

```yaml
# k8s/web-deployment.yaml
apiVersion: ___                       # YOUR TASK: which apiGroup/version owns Deployment?
kind: ___                             # YOUR TASK
metadata:
  name: ___                           # YOUR TASK: lab's headline name
  labels:
    ___: ___                          # YOUR TASK: the label the Service selector will match
spec:
  replicas: ___                       # YOUR TASK: how many web pods? (lecture 9 + Task 4 scale)
  selector:
    matchLabels:
      ___: ___                        # MUST match the pod template labels below
  strategy:
    type: ___                         # YOUR TASK: which strategy for zero-downtime updates?
    rollingUpdate:
      maxUnavailable: ___             # YOUR TASK: 0 = strict zero-downtime
      maxSurge: ___
  template:
    metadata:
      labels:
        ___: ___                      # MUST match selector.matchLabels EXACTLY
    spec:
      containers:
        - name: ___                   # YOUR TASK
          image: ___                  # YOUR TASK: your Lab 2 image. Two valid forms:
                                      #   - GHCR pull: ghcr.io/<you>/devops-info-service:1.0.0  (public package — Lab 2 Task 7)
                                      #   - Local tag: devops-info-service:lab02-multi          (must `k3d image import` — see §2.3)
          imagePullPolicy: ___        # YOUR TASK: which policy lets a k3d-imported image work?
                                      #            (hint: see Setup note about local images + Common Pitfalls)
          ports:
            - name: ___               # YOUR TASK: name this port (e.g. `http`). Lab 10's Helm chart
                                      #            and Lab 16's ServiceMonitor both target the port BY NAME.
                                      #            Pick a name now or rewrite both labs later.
              containerPort: ___      # YOUR TASK: the port your Lab 1 app listens on
              protocol: TCP
          resources:
            requests:
              cpu: ___                # YOUR TASK: scheduler reserves this — see lecture 9 slide 15
              memory: ___
            limits:
              cpu: ___                # YOUR TASK
              memory: ___             # YOUR TASK: memory-OOMKill ceiling — set tightly
          livenessProbe:
            httpGet:
              path: ___               # YOUR TASK: which endpoint from Lab 1? (hint: cheap, not the app root)
              port: ___
            initialDelaySeconds: ___  # YOUR TASK
            periodSeconds: ___
          readinessProbe:
            httpGet:
              path: ___               # YOUR TASK
              port: ___
            periodSeconds: ___        # YOUR TASK: fail fast — readiness gates traffic
```

**Почему важен каждый пропуск (прочитайте это перед заполнением):**

- **`apiVersion` / `kind`** — Deployment живёт в `apps/v1` (единственная GA-группа/версия для него). `Pod` — это `v1`, `Service` — это `v1`. Запомните таблицу; к лабораторной 13 вы будете писать её на автомате.
- **Треугольник label** — `metadata.labels`, `spec.selector.matchLabels` и `spec.template.metadata.labels` — это три *отдельных* словаря, которым всем нужна одна и та же пара ключ/значение. Селектор **неизменяем после создания**; если вы ошиблись с ключом, придётся `kubectl delete` и применить заново.
- **`imagePullPolicy`** — `Always` повторно тянет образ при каждом перезапуске; **падает на k3d для локально собранных образов**, потому что в реестре их нет. `IfNotPresent` использует то, что уже есть в containerd (а это то, что наполняет `k3d image import`). `Never` — параноидальный вариант. Выбирайте осознанно.
- **`resources.requests`** — их читает **планировщик**, чтобы выбрать узел. Слишком мало — шумные соседи будут вас голодать; слишком много — ваши pod'ы повиснут в `Pending`, потому что ни на одном узле нет запаса.
- **`resources.limits.memory`** — после этого порога ядро делает OOMKill контейнера. Ставьте плотно, чтобы утечка проявлялась как перезапуск, а не как смерть узла из-за swap. Лимиты **CPU** вызывают тихое троттлингование — там будьте мягче.
- **Пробы** — падение `livenessProbe` = контейнер перезапускается. Падение `readinessProbe` = pod убирается из списка эндпоинтов Service (без перезапуска). Обе пробы, указывающие на корень приложения `/`, — это самая распространённая производственная ловушка (медленная страница = цикл перезапусков = простой). Выберите `/health` или `/healthz`, который возвращает 200 без обращений к БД.
- **`strategy.rollingUpdate.maxUnavailable: 0`** — именно это гарантирует нулевой простой в задаче 4. Значение по умолчанию (25%) означает, что во время обновления один из трёх ваших pod'ов отсутствует.

### 2.2 — Service

`ВАША ЗАДАЧА`: напишите `k8s/web-service.yaml`. Выберите **тип Service**, который делает приложение доступным с вашего ноутбука без port-forward (на слайде 9 лекции 9 есть таблица; на k3d это дружелюбный к разработке тип).

```yaml
# k8s/web-service.yaml
apiVersion: ___                       # YOUR TASK
kind: ___                             # YOUR TASK
metadata:
  name: ___                           # YOUR TASK: kube-DNS will resolve THIS name inside the cluster
spec:
  type: ___                           # YOUR TASK: see lecture 9 slide 9 — pick the one that exposes :NodePort on every node
  selector:
    ___: ___                          # MUST match the Deployment pod labels — kube-proxy uses this to build endpoints
  ports:
    - name: ___                       # YOUR TASK: same name you gave the containerPort (e.g. `http`).
                                      #            Lab 16's ServiceMonitor uses this string, not the number.
      port: ___                       # YOUR TASK: the port the Service listens on (cluster-side)
      targetPort: ___                 # YOUR TASK: prefer the port NAME (e.g. `http`) over a number —
                                      #            keeps the Service stable when the container port changes
      protocol: TCP
      # nodePort: ___                 # OPTIONAL: pin it (30000–32767), or let K8s pick
```

**Почему важен каждый пропуск:**

- **`name` Service** — именно это разрешает kube-DNS внутри кластера. `curl http://web/` из любого другого pod'а попадает в этот Service. Выберите что-то короткое и стабильное; переименование Service — это ловушка (DNS-клиенты кэшируют).
- **`type`** — `ClusterIP` (по умолчанию) только внутренний; `NodePort` выставляет высокий порт на каждом узле; `LoadBalancer` провижинит облачный LB (klipper-lb на k3d). Для локальной разработки NodePort работает, как только вы смапили порт хоста; `LoadBalancer` тоже работает на k3d благодаря klipper. Выберите один и обоснуйте.
- **`port` vs `targetPort`** — `port` — это то, куда *клиенты* попадают на IP Service; `targetPort` — это то, что слушает **контейнер**. Несовпадение здесь = эндпоинты есть, но связи нет. Не ставьте их равными слепо — это разные понятия.
- **Именованные порты** — `ports[].name: http` (и `targetPort: http`, ссылающийся на `ports[].name` контейнера) — это **не необязательный лоск**. `ServiceMonitor.spec.endpoints[].port` в лабораторной 16 — это **строка** (имя порта), а не число — голый числовой порт молча не разрешается, и оператор пропустит ваш сервис. Задайте имя сейчас или переписывайте этот Service потом.
- **`selector`** — должен точно совпадать с labels pod'а. `kubectl get endpoints web` — ваш отладочный оракул: если он пуст, ваш селектор не совпадает ни с одним pod'ом.

### 2.3 — Загрузите образ и примените

**Два пути** — выберите один в зависимости от того, публичен ли ваш образ из лабораторной 2 в GHCR:

**Путь A — GHCR (рекомендуется).** Ваш `ghcr.io/<you>/devops-info-service:1.0.0` публичен (согласно лабораторной 2 §7). containerd k3d тянет его напрямую; **`k3d image import` не нужен**. Переходите к `kubectl apply`.

**Путь B — только локальная сборка.** Ваш образ существует только в Docker вашего ноутбука (`devops-info-service:lab02-multi` или подобный) — containerd k3d о нём никогда не слышал. Вы **обязаны** импортировать его:

```bash
docker images | grep devops-info-service         # confirm the tag exists locally
k3d image import ___ --cluster devops            # YOUR TASK: paste the exact `<name>:<tag>` from above
```

> 💡 Узлы k3d запускают k3s в своих собственных контейнерах со своим собственным containerd — демон Docker вашего ноутбука им не виден. `k3d image import` — это способ преодолеть этот разрыв (он делает `docker save | docker load` в каждый узел k3d). Если `kubectl get pods` показывает `ErrImagePull`/`ImagePullBackOff`, а вы уверены, что тег верный, вы забыли этот шаг.

Как только образ доступен (любым путём):

```bash
kubectl apply -f k8s/web-deployment.yaml
kubectl apply -f k8s/web-service.yaml

kubectl rollout status deploy/web              # blocks until 3/3 ready
kubectl get pods -l app=web -o wide            # YOUR TASK: confirm pods spread across all 3 nodes
kubectl get endpoints web                      # MUST list 3 pod IPs once readiness passes
```

> 💡 **Лестница отладки, когда с первого раза не работает:**
> 1. `kubectl get pods` — `ImagePullBackOff` = неверны реестр/учётные данные/`imagePullPolicy`; `CrashLoopBackOff` = контейнер завершается, смотрите логи.
> 2. `kubectl describe pod <name>` — внизу в разделе **Events** находится настоящая причина отказа.
> 3. `kubectl logs <pod-name>` — stdout вашего приложения.
> 4. `kubectl get endpoints web` — пустой список = несовпадение selector/label (треугольник label неверен).

### 2.4 — Подтверждение работы

**Вставьте в `docs/LAB09.md`:**

- `kubectl get deploy,rs,pods,svc,endpoints -l app=web` — должно показать **3/3** ready и **3 IP эндпоинтов**
- `kubectl get pods -l app=web -o wide` — колонка **NODE** должна показывать все 3 узла (доказывает многоузловое планирование — это половина причины, по которой вы запускали `--agents 2`)
- Скриншот `kubectl port-forward svc/web 8080:80` + `curl -s localhost:8080/health`, доказывающий, что Service связан с работающим приложением
- Ваш выбор `imagePullPolicy` + 1 предложение с обоснованием
- Ваши requests/limits ресурсов + 1 предложение с обоснованием

---

## Задача 3 — Разверните сервис `echo` (2 балла)

Второй сервис. Прочитайте `plumbing/echo/README.md` о контракте эндпоинтов — вы **не** собираете и не изменяете этот код.

| Путь | Поведение |
|---|---|
| `GET /ping` | Возвращает `pong\n` — ваша главная проверка в задаче 4 |
| `* /echo` | JSON с `hostname` + счётчик запросов — полезно для наблюдения балансировки нагрузки |
| `GET /healthz` | Возвращает `ok` (200) — подключите к пробам |
| `GET /metrics` | Формат Prometheus (вы будете собирать это в лабораторной 16) |

Образ — `ghcr.io/inno-devops-labs/echo:v1`; он слушает **порт 8081**.

### 3.1 — Deployment echo

`ВАША ЗАДАЧА`: напишите `k8s/echo-deployment.yaml`. Та же форма, что у `web`, но другие labels, другой образ, другой порт, другое число реплик — **2 реплики** обязательны, потому что задаче 4 нужно, чтобы Service балансировал по кругу между **двумя** pod'ами.

```yaml
# k8s/echo-deployment.yaml
apiVersion: ___                       # YOUR TASK
kind: ___                             # YOUR TASK
metadata:
  name: ___                           # YOUR TASK
  labels:
    ___: ___                          # YOUR TASK: must be DIFFERENT from web's label value
spec:
  replicas: ___                       # YOUR TASK: read the prose above — why two?
  selector:
    matchLabels:
      ___: ___
  template:
    metadata:
      labels:
        ___: ___
    spec:
      containers:
        - name: ___
          image: ___                  # YOUR TASK: the published echo image — see plumbing/echo/README.md
          ports:
            - name: ___               # YOUR TASK: name the port (e.g. `http`). Same reason as the web Deployment.
              containerPort: ___      # YOUR TASK: see echo README — what port?
              protocol: TCP
          resources:
            requests: { cpu: ___, memory: ___ }    # YOUR TASK: echo is a tiny Go binary
            limits:   { cpu: ___, memory: ___ }
          readinessProbe:
            httpGet:
              path: ___               # YOUR TASK: echo's readiness endpoint — README has it
              port: ___
            periodSeconds: ___
          livenessProbe:
            httpGet:
              path: ___
              port: ___
            initialDelaySeconds: ___
            periodSeconds: ___
```

> 💡 **Go-бинарники крошечные.** Ставьте `requests.memory` в однозначные MiB, а `requests.cpu` — примерно в 10–50m. Если скопируете цифры `web`, вы избыточно зарезервируете ёмкость кластера, и pod'ы уйдут в `Pending`.

### 3.2 — Service echo

`ВАША ЗАДАЧА`: напишите `k8s/echo-service.yaml`. Этот — `ClusterIP` (только внутренний — его вызывает pod `web`; доступ с ноутбука не нужен). Межсервисный вызов в §4.1 попадёт в `http://echo:___/ping` — выберите `port` Service, при котором этот URL чистый (на слайде 9 лекции 9 есть соглашение).

```yaml
# k8s/echo-service.yaml
apiVersion: ___
kind: ___
metadata:
  name: ___                           # YOUR TASK: the DNS name `web` will use to reach echo
spec:
  type: ___                           # YOUR TASK: internal-only — which type?
  selector:
    ___: ___                          # MUST match echo pod labels (NOT web's)
  ports:
    - name: ___                       # YOUR TASK: same name you gave the containerPort
      port: ___                       # YOUR TASK: HTTP-default port, so `http://echo/ping` works with no `:port`
      targetPort: ___                 # YOUR TASK: prefer the port NAME (string) over the container port number
      protocol: TCP
```

> 💡 **Почему `port: 80` у Service?** Потому что `http://echo/ping` (без порта) по умолчанию использует 80. Если задать `port: 8081`, вызывающим придётся писать `http://echo:8081/ping` — работает, но лекция/документация/ваш будущий чарт Helm все предполагают чистую форму. Порт Service и порт контейнера **развязаны** — в этом вся суть.

### 3.3 — Примените и проверьте

```bash
kubectl apply -f k8s/echo-deployment.yaml
kubectl apply -f k8s/echo-service.yaml

kubectl get pods,svc,endpoints -l app=echo     # 2 pods Ready, 2 endpoint IPs
kubectl rollout status deploy/echo
```

### 3.4 — Подтверждение работы

**Вставьте в `docs/LAB09.md`:**

- `kubectl get pods,svc,endpoints -l app=echo` — **2** pod'а Ready, у Service **2** эндпоинта
- Один скриншот `kubectl describe svc echo`, показывающий строки `Selector` и `Endpoints`
- 1–2 предложения о том, **почему ваши `requests` у echo меньше, чем у `web`** — обоснование крошечного Go-бинарника

---

## Задача 4 — Сетевое взаимодействие между сервисами, масштабирование, раскатка (2 балла) ← **главная задача**

### 4.1 — Доказательство kube-DNS — самая важная команда в этой лабораторной

`ВАША ЗАДАЧА`: из **внутри pod'а `web`** вызовите эндпоинт `/ping` сервиса `echo` по его **DNS-имени** и зафиксируйте `pong`. Без port-forward. Без NodePort. Запрос должен пройти pod → DNS Service → kube-proxy → pod echo, а разрешение имён выполняет kube-DNS.

```bash
WEBPOD=$(kubectl get pod -l ___=___ -o jsonpath=___)    # YOUR TASK: get the name of any web pod
                                                        #            (hint: -o jsonpath='{.items[0].metadata.name}')

kubectl exec $WEBPOD -- ___ ___                         # YOUR TASK: hit http://echo/ping
                                                        #            (hint: which tool? — see "If curl is missing" below)
# expected output:
# pong
```

**Почему это важно.** Если вы получили `pong`, шесть вещей сработали одновременно:
1. **kube-DNS** в `kube-system` разрешил `echo` → в ClusterIP Service
2. **Селектор** Service совпал с labels pod'а echo
3. **kube-proxy** запрограммировал правила iptables/IPVS для маршрутизации IP Service → на один из двух IP pod'ов
4. **readinessProbe** pod'а echo прошла, поэтому он появился в `endpoints`
5. Внутренняя сеть кластера передала запрос через границу узла (вероятно — `web` и `echo`, скорее всего, оказались на разных узлах)
6. **Треугольник label** в ваших манифестах согласован сквозным образом

Если хоть одна из них неверна, вы получите таймаут или DNS NXDOMAIN. **Сохраните вывод.** Это главный артефакт лабораторной 9.

<details>
<summary>💡 Если в вашем образе <code>web</code> нет <code>curl</code></summary>

В slim-образе из лабораторной 2, скорее всего, нет `curl`. Два варианта — оба приемлемы, если вызов исходит **изнутри кластера**:

```bash
# Option A — use python (Lab 1 left you a Python interpreter)
kubectl exec $WEBPOD -- python -c \
  "import urllib.request; print(urllib.request.urlopen('http://echo/ping').read().decode())"

# Option B — throwaway client pod inside the cluster
kubectl run tmp --rm -it --image=curlimages/curl:8.11.0 --restart=Never -- \
  curl -s http://echo/ping
```

Что **НЕ** засчитывается: `curl localhost:8088/ping` после `port-forward svc/echo` — это доказывает, что ваш ноутбук достаёт до echo, а не что это может `web`. Вся суть — в вызове **pod-to-pod**.

</details>

### 4.2 — Балансировка нагрузки Service между двумя pod'ами echo

У Service echo 2 эндпоинта. Ударьте по `/echo` несколько раз — ответ содержит `hostname` отвечающего pod'а, так что вы увидите, как kube-proxy распределяет трафик по кругу.

```bash
kubectl exec $WEBPOD -- sh -c '___'                     # YOUR TASK: hit http://echo/echo 6+ times in a loop,
                                                        #            extract or print the hostname per call
# expected: hostname rotates between the 2 echo pods (roughly 50/50 over enough calls)
```

> 💡 Round-robin по умолчанию действует на соединение, а не на запрос. Если вы видите одно и то же hostname каждый раз, ваш клиент переиспользует одно соединение — добавляйте новый запрос каждый раз (`-H 'Connection: close'` для curl, или просто зациклите свежие вызовы `urlopen` в Python).

### 4.3 — Масштабируйте `web` до 5 реплик

`ВАША ЗАДАЧА`: масштабируйте вверх. Используйте **декларативный** путь (измените `replicas:` в манифесте и сделайте `kubectl apply -f`) — императивный `kubectl scale` работает, но не переживает следующий `apply` вашего манифеста, а это та самая GitOps-убийственная ловушка, которую вы снова встретите в лабораторной 13.

```bash
# After editing the manifest:
kubectl apply -f k8s/web-deployment.yaml
kubectl get pods -l app=web -w           # watch new pods come up
kubectl get endpoints web                # 5 pod IPs once readiness passes
```

### 4.4 — Раскатка + откат

Измените образ `web` на другой тег (пересоберите образ из лабораторной 2 с новым тегом или временно измените `name:` контейнера — что угодно, что сделает хеш шаблона pod'а другим). Примените и наблюдайте:

```bash
kubectl apply -f k8s/web-deployment.yaml
kubectl rollout status deploy/web        # blocks until new ReplicaSet is fully ready
kubectl rollout history deploy/web       # shows both revisions

kubectl rollout undo deploy/web          # back to the previous revision
kubectl rollout status deploy/web
```

С `maxUnavailable: 0` (из §2.1) `kubectl get endpoints web` ни в какой момент не должен опускаться ниже 5. **Проверьте это в другой оболочке.**

### 4.5 — Подтверждение работы

**Вставьте в `docs/LAB09.md`:**

- **Доказательство kube-DNS** — вашу команду `kubectl exec $WEBPOD -- ... http://echo/ping` и её вывод `pong`. **Это главный артефакт.**
- Скриншот балансировки нагрузки — 6+ hostname'ов, показывающих, что **оба** имени pod'ов echo появляются примерно равномерно
- `kubectl get pods -l app=web -o wide` после масштабирования до 5 — 5 pod'ов, распределённых по узлам
- `kubectl rollout history deploy/web` — видно минимум 2 ревизии
- Вывод `kubectl rollout undo` + `kubectl rollout status`, подтверждающий, что откат прошёл успешно
- 2–3 предложения о самом полезном выводе `kubectl describe` / `kubectl get events`, который вы встретили при отладке — какая именно строка `Events:` дала вам ответ?

---

## Задача 5 — Документация (1 балл)

`ВАША ЗАДАЧА`: напишите `k8s/docs/LAB09.md` с этими разделами по порядку:

1. **Архитектура** — диаграмма Mermaid, показывающая `User → web Service → 3× web pods` и `web pod → echo Service → 2× echo pods`, с отмеченным на второй стрелке разрешением через kube-DNS
2. **Кластер** — ваша команда `k3d cluster create` + исследование из 3 вопросов из §1.1
3. **Манифесты** — по одному короткому абзацу на файл: какие labels, какой тип Service, какое число реплик, какие эндпоинты проб — и **почему** для каждого неочевидного выбора
4. **Доказательства межсервисного взаимодействия** — скриншот `pong` из §4.1 с предложением, объясняющим каждую из шести вещей, которые только что сработали
5. **Операции** — доказательства масштабирования, раскатки, отката из §4.3–4.4
6. **Трудности и решения** — хотя бы одна настоящая (не «я был новичком в YAML»); включите строку `kubectl describe`, которая вас разблокировала

Включите **фрагменты** манифестов (не целые файлы — они уже закоммичены) и реальные скриншоты CLI из задач 1–4.

---

## Бонусная задача — Ingress с TLS через Traefik (2 балла)

Меньше подсказок. k3d поставляет Traefik из коробки (это LoadBalancer за портами хоста `:8080`/`:8443`, которые вы смапили в §1.2) — **устанавливать контроллер не нужно**. Используйте `*.localhost` (автоматически разрешается в `127.0.0.1` — без правок `/etc/hosts`).

`ВАША ЗАДАЧА`: маршрутизируйте `web.localhost` → Service `web` и `echo.localhost` → Service `echo`, оба по HTTPS, через единый `Ingress`.

1. **Самоподписанный сертификат + Secret**, покрывающий оба hostname:
   ```bash
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout tls.key -out tls.crt \
     -subj "/CN=web.localhost" \
     -addext "subjectAltName=DNS:web.localhost,DNS:echo.localhost"
   kubectl create secret tls ___ --key tls.key --cert tls.crt   # YOUR TASK: pick a Secret name
   ```

2. **`k8s/ingress.yaml`** — форма Ingress:

```yaml
apiVersion: ___                       # YOUR TASK: which group/version owns Ingress? (NOT extensions/v1beta1 — that's gone)
kind: ___
metadata:
  name: ___
spec:
  ingressClassName: ___               # YOUR TASK: k3d's built-in controller name (lecture 9 slide 13)
  tls:
    - hosts: [___, ___]               # YOUR TASK: both hostnames
      secretName: ___                 # YOUR TASK: matches the Secret name above
  rules:
    - host: ___                       # YOUR TASK: web's hostname
      http:
        paths:
          - path: ___                 # YOUR TASK
            pathType: ___             # YOUR TASK: Prefix or Exact?
            backend:
              service:
                name: ___             # YOUR TASK: which Service is this rule routing to?
                port:
                  number: ___         # YOUR TASK: the Service's port (NOT the targetPort).
                                      #            Or use `name: http` to reference the named Service port.
    - host: ___                       # YOUR TASK: echo's hostname
      http:
        paths:
          - path: ___
            pathType: ___
            backend:
              service:
                name: ___
                port:
                  number: ___         # (same options as above — number or name)
```

3. **Проверьте** через порт хоста, который вы смапили при создании кластера:
   ```bash
   curl -k https://echo.localhost:8443/ping    # → pong, through Traefik + TLS
   curl -k https://web.localhost:8443/health   # → your app's health JSON
   ```

> 💡 **Маршрутизация по хосту** (один Service на hostname) позволяет избежать middleware для перезаписи пути, так что каждый backend видит путь запроса неизменным. Альтернатива — по пути (`/web` → web, `/echo` → echo на одном hostname) — требует middleware Traefik для отрезания префикса; для двух сервисов не стоит усложнения.

**Доказательства (вставьте в `docs/LAB09.md`):**
- `kubectl get pods -n kube-system | grep traefik` — контроллер Running
- `kubectl get ingress` — ваш Ingress с видимыми двумя хостами
- Оба скриншота `curl -k https://...localhost:8443/...` с реальным выводом
- 1–2 предложения о том, что Ingress даёт вам сверх NodePort Service из §2.2

---

## Как сдавать

```bash
git switch -c lab09
git add k8s/
git commit -m "feat(lab09): web + echo on k3d — cross-service kube-DNS proven"
git push -u origin lab09
```

Откройте **два** PR:

- `your-fork:lab09` → `course-repo:master` *(на проверку)*
- `your-fork:lab09` → `your-fork:master` *(сливается в ваш собственный main, когда готово)*

Чек-лист PR:

```text
- [ ] Task 1 done — 3-node k3d cluster on K8s 1.36.1, evidence captured
- [ ] Task 2 done — web Deployment (3 replicas) + Service, label triangle correct, probes on cheap endpoint
- [ ] Task 3 done — echo Deployment (2 replicas) + ClusterIP Service, sized for a tiny Go binary
- [ ] Task 4 done — kubectl exec from inside web pod returns `pong` from echo; LB rotation shown; scaled to 5; rolled out & back
- [ ] Task 5 done — LAB09.md with all 6 sections + Mermaid diagram + the pong capture
- [ ] Bonus done — Ingress over HTTPS via Traefik, both hostnames reachable
```

---

## Критерии приёмки

### Задача 1 — кластер k3d (2 балла)
- ✅ `kubectl version` показывает server `1.36.x`
- ✅ `kubectl get nodes -o wide` показывает **3 узла**, все `Ready`
- ✅ В команде `k3d cluster create` присутствуют мапы портов хоста LoadBalancer `:80→:8080` и `:443→:8443`
- ✅ Ответы на исследование из §1.1 в `docs/LAB09.md`

### Задача 2 — сервис web (3 балла)
- ✅ `web-deployment.yaml` и `web-service.yaml` написаны вручную
- ✅ Треугольник label согласован (labels Deployment = selector.matchLabels = labels template)
- ✅ **И порт контейнера, И порт Service названы** (например, `name: http`) — это требуется в лабораторных 10/16
- ✅ 3 реплики Ready; `kubectl get endpoints web` показывает **3 IP**
- ✅ Заданы **requests И limits** ресурсов; обе пробы подключены к эндпоинту вида `/health`, а не к корню приложения
- ✅ Pod'ы распределены по всем 3 узлам (скриншот `-o wide`)

### Задача 3 — сервис echo (2 балла)
- ✅ `echo-deployment.yaml` использует `ghcr.io/inno-devops-labs/echo:v1` (без собственных сборок)
- ✅ **2** реплики Ready; у ClusterIP Service **2** эндпоинта
- ✅ Пробы подключены к `/healthz:8081` (фактический эндпоинт готовности echo, согласно `plumbing/echo/README.md`)
- ✅ Ресурсы меньше, чем у web (крошечный Go-бинарник)

### Задача 4 — межсервисное взаимодействие + операции (2 балла)
- ✅ **`kubectl exec` в pod web + вызов `http://echo/ping` возвращает `pong`** — доказательство kube-DNS зафиксировано
- ✅ Скриншот балансировки показывает **оба** hostname pod'ов echo
- ✅ `web` масштабирован до 5; список эндпоинтов достигает 5; простой не виден
- ✅ Раскатка + откат показаны с доказательством из `kubectl rollout history`

### Задача 5 — документация (1 балл)
- ✅ Все 6 разделов в `k8s/docs/LAB09.md`; включена диаграмма Mermaid; скриншот pong — главный артефакт

### Бонус — Ingress + TLS (2 балла)
- ✅ Самоподписанный Secret создан с обоими SAN
- ✅ Ingress использует `ingressClassName: traefik`, маршрутизируются оба хоста
- ✅ Оба вызова `curl -k https://...localhost:8443/...` успешны

---

## Рубрика

| Задача | Баллы | Критерии |
|------|-------:|----------|
| **Задача 1** — кластер k3d | **2** | Поднят 3-узловой кластер K8s 1.36, ответы на исследование, мапы портов для бонуса |
| **Задача 2** — сервис web | **3** | Написанные вручную Deployment + Service, верный треугольник label, пробы на дешёвом эндпоинте, requests+limits, 3 эндпоинта |
| **Задача 3** — сервис echo | **2** | Развёрнут предоставленный образ (2 реплики), ClusterIP Service, пробы на `/healthz` |
| **Задача 4** — межсервисное взаимодействие + операции | **2** | `pong` изнутри pod web, ротация LB, масштабирование+раскатка+откат |
| **Задача 5** — документация | **1** | 6 разделов, Mermaid, скриншот pong как главный артефакт |
| **Бонус** — Ingress + TLS | **2** | Traefik Ingress, оба hostname по HTTPS |
| **Итого** | **12** | 10 основных + 2 бонусных |

---

## Ресурсы

<details>
<summary>📚 Документация Kubernetes</summary>

- [Kubernetes 1.36 "Haru" release notes](https://kubernetes.io/blog/2026/04/22/kubernetes-v1-36-release/)
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Services & networking](https://kubernetes.io/docs/concepts/services-networking/service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Liveness, readiness, startup probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [kubectl cheat sheet](https://kubernetes.io/docs/reference/kubectl/quick-reference/)

</details>

<details>
<summary>🛠️ Инструменты</summary>

- [k3d](https://k3d.io/) — k3s in Docker
- [k3s docs](https://docs.k3s.io/)
- [k9s](https://k9scli.io/) — TUI for kubectl
- [kubectx/kubens](https://github.com/ahmetb/kubectx) — context + namespace switcher
- [stern](https://github.com/stern/stern) — multi-pod log tailing

</details>

<details>
<summary>⚠️ Частые ловушки (из реальных прогонов)</summary>

- **Несовпадение label-selector — ошибка №1 в YAML для K8s.** У Deployment есть *три* места, где появляются labels: `metadata.labels`, `spec.selector.matchLabels` и `spec.template.metadata.labels`. `spec.selector` у Service — четвёртое. Все они должны согласовываться. Симптом: `kubectl get endpoints <svc>` пуст, хотя pod'ы Running. Селектор **неизменяем** после создания Deployment — если вы ошиблись, придётся `kubectl delete deploy/...` и применить заново (через `kubectl edit` не выбраться).

- **`imagePullPolicy: Always` падает для локально собранных образов на k3d.** `k3d image import` наполняет containerd кластера напрямую; нет реестра, хранящего ваш тег `:latest`. `Always` повторно тянет при каждом перезапуске и получает `ErrImagePull` / `ImagePullBackOff`. Используйте `IfNotPresent` для локально импортированных образов (это также значение по умолчанию, когда ваш тег — что угодно, кроме `:latest` — но **не полагайтесь на значение по умолчанию**; объявляйте его явно).

- **NodePort на k3d требует смапленного порта хоста при создании кластера.** klipper-lb k3d выставляет порты класса LoadBalancer, которые вы указали в `-p`, но NodePort в диапазоне 30000–32767 недостижим с вашего ноутбука, если вы либо (a) не добавили `-p "3xxxx:3xxxx@server:0"` при создании кластера, либо (b) не сделали `kubectl port-forward`. Сервисы `LoadBalancer` и `port-forward` оба работают без церемоний; голый NodePort — нет.

- **`livenessProbe`, указывающая на главную страницу приложения.** Когда трафик подскакивает, ваш обработчик замедляется. Liveness получает таймаут, K8s перезапускает контейнер, очередь выливается на оставшиеся pod'ы, *они* замедляются под удвоенной нагрузкой — **каскадные перезапуски** ровно в тот момент, когда вам нужно, чтобы система оставалась на ногах. Liveness должна указывать на **дешёвый, внутрипроцессный** сигнал (`/health`, возвращающий 200 без обращений к БД). Именно поэтому лабораторная 1 заставила вас отдельно сделать `/health`.

- **Отсутствующая или медленная `readinessProbe` вызывает провалы при раскатке.** Без readiness K8s добавляет pod в эндпоинты Service в момент, когда контейнер *запустился* — до того, как ваше приложение реально обслуживает. При раскатке это означает несколько секунд `connection refused` на каждой замене. Readiness с `periodSeconds: 3–5` и низким `failureThreshold` держит неготовые pod'ы вне списка эндпоинтов и вне трафика.

- **Путаница `port` vs `targetPort`.** `port` — это то, куда *клиенты* попадают на Service; `targetPort` — это то, что слушает **контейнер**. Частая ошибка: `port: 8081` на Service echo. Работает — но теперь каждый вызывающий пишет `http://echo:8081/ping`, и ваш будущий чарт Helm, ApplicationSet из лабораторной 13 и ServiceMonitor из лабораторной 16 должны все особо обрабатывать этот порт. Выбирайте `port: 80` для HTTP-сервисов, чтобы URL только с DNS работали.

- **Слишком низкие requests ресурсов → голодание из-за шумных соседей.** У k3d на ноутбуке конечная память. Если `requests: 64Mi` у `web` реалистичны, а вы ставите `8Mi`, планировщик переполняет узлы, и ваши pod'ы выселяются по OOM под любой реальной нагрузкой. Ставьте `requests` равными тому, что ваше приложение реально использует в простое + небольшой буфер, а не минимуму, с которым оно может загрузиться.

- **`kubectl edit` вместо `kubectl apply -f`.** `edit` мутирует живой объект напрямую; ваш манифест в git больше не соответствует реальности. Следующий `apply` откатит ваш хотфикс. В мире GitOps (лабораторная 13+) это гонка на этапе развёртывания. Всегда редактируйте YAML, делайте `apply -f`, коммитьте.

- **В контейнере нет `curl`/`wget`, и вы хватаетесь за неправильный обходной путь.** Не делайте `port-forward`, чтобы «протестировать» межсервисные вызовы — это доказывает, что ваш ноутбук достаёт до echo, а не что это может `web`. Используйте `kubectl run tmp --rm -it --image=curlimages/curl ...` или `kubectl exec $WEBPOD -- python -c "..."`, чтобы вызов исходил **изнутри кластера**.

- **Встроенный Traefik в k3d vs мышечная память на ingress-nginx.** Онлайн-руководства предполагают ingress-nginx (`ingressClassName: nginx`, аннотации `nginx.ingress.kubernetes.io/*`). На k3d это Traefik (`ingressClassName: traefik`, аннотации `traefik.ingress.kubernetes.io/*`). Основные поля `Ingress` в Kubernetes переносимы; аннотации — нет.

</details>

<details>
<summary>🔍 Шпаргалка по отладке</summary>

```bash
kubectl describe pod <name>           # bottom Events section = root-cause oracle
kubectl get events --sort-by=.lastTimestamp  # cluster-wide event stream
kubectl logs <pod> --previous         # logs from the previous (crashed) container
kubectl get endpoints <svc>           # empty = selector/label mismatch
kubectl exec -it <pod> -- /bin/sh     # shell into the pod (if it has one)
kubectl run net-debug --rm -it --image=nicolaka/netshoot --restart=Never -- bash
                                       # DNS + network sandbox with dig, nslookup, curl, tcpdump
```

</details>

---

## Взгляд вперёд

| Лабораторная | Что добавляет к этому стеку |
|---:|---|
| 10 | Переупаковка этих манифестов в чарт **Helm 4**; `echo` становится подчартом |
| 11 | Замена открытой конфигурации на **Secrets** (и знакомство с OpenBao) |
| 12 | **ConfigMaps** + **PVC** — инъекция конфигурации + выживание состояния при перезапусках pod'ов |
| 13 | **ArgoCD** GitOps — `web` + `echo` развёрнуты через `ApplicationSet` для 2 окружений |
| 14 | **Argo Rollouts** — canary-развёртывание Deployment `echo` с прогрессивным сдвигом трафика |
| 16 | **kube-prometheus-stack** — сбор `/metrics` у `echo` через `ServiceMonitor` |

---

**Удачи!** ☸️

> **Помните:** сетевая модель K8s щёлкает только тогда, когда у вас есть **второй** сервис, с которым можно поговорить. Тот `pong`, вернувшийся от `echo` на `curl`, запущенный *внутри* вашего pod'а `web` — это момент, когда всё из лекции 9 (Pod, Service, label selector, kube-DNS, endpoints, kube-proxy) складывается вместе. Если из лабораторной сохранится только один скриншот, пусть это будет он.
