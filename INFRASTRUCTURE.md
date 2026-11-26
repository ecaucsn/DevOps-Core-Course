# Инфраструктура для лабораторных (1–18)

Практическое руководство по подготовке окружения для курса **DevOps Engineering: Core Practices**.
Всё ставится **локально, без sudo, за $0**: бинарники и Python/Node — в пользовательские каталоги,
Kubernetes — в Docker через k3d, облако не требуется (кроме бесплатного Cloudflare для лаб. 17).

> Окружение проверено: Ubuntu 24.04.4 LTS, 8 vCPU, 15 ГиБ RAM, 188 ГБ свободно, Docker 29.1.3.

> ⚠️ **Две особенности этой машины:**
> 1. Порт **8080 уже занят** другой службой — публикуйте приложение на **8088** (внутри контейнера/пода остаётся 8080).
> 2. Домены `releases.hashicorp.com`, `registry.opentofu.org`, `registry.terraform.io` и
>    сервер плагинов Pulumi недоступны (403/404). Поэтому Terraform → OpenTofu, а
>    Docker-провайдер для лаб. 4 ставится из GitHub в локальное зеркало.

---

## 1. Быстрый старт

```bash
# 1) проверка окружения
bash scripts/setup/00-preflight.sh

# 2) установка всех фаз (идемпотентно)
bash scripts/setup/run-all.sh

# 3) только проверки (не меняет систему)
bash scripts/setup/verify.sh

# 4) проверка вместе с созданием тестового k3d-кластера
bash scripts/setup/verify.sh --cluster
```

Отдельные фазы:

| Скрипт | Что ставит |
|---|---|
| `00-preflight.sh` | проверки (ничего не меняет) |
| `10-base.sh` | uv, Python 3.13, Trivy, yq |
| `20-iac.sh` | OpenTofu (+ shim `terraform`), Pulumi, tflint |
| `30-ansible.sh` | ansible-core, ansible-lint, коллекции |
| `40-k8s.sh` | kubectl, k3d, Helm, ArgoCD CLI, плагин Argo Rollouts, bao |
| `50-edge-nix.sh` | Wrangler (Node 22), Nix через nix-portable |
| `verify.sh` | smoke-тесты |

Переустановить компонент принудительно: `FORCE=1 bash scripts/setup/40-k8s.sh`.

Всё, что можно, ставится в `~/.local/bin` (уже в `PATH`). Python-инструменты — через `uv tool`,
Node — через `nvm` (`~/.nvm`). **Пароль sudo не используется.**

---

## 2. Что установлено

| Инструмент | Версия | Где | Для лаб. |
|---|---|---|---|
| Docker Engine / Compose | 29.1.3 / 2.40.3 | система (уже был) | 2, 7–9, 18 |
| uv | 0.13.10 | `~/.local/bin/uv` | менеджер Python |
| Python (uv) | 3.13.18 | `~/.local/share/uv` | 1–3 |
| Trivy | 0.76.2 | `~/.local/bin/trivy` | 2–3 |
| yq | 4.54.3 | `~/.local/bin/yq` | утилита |
| OpenTofu / `terraform` (shim) | 1.13.10 | `~/.local/bin/tofu` | 4 |
| Pulumi | 3.278.0 | `~/.local/bin/pulumi` | 4 |
| tflint | 0.66.0 | `~/.local/bin/tflint` | 4 (бонус) |
| ansible-core | 2.22.0 | `uv tool` | 5–6 |
| ansible-lint | 26.11.1 | `uv tool` | 5–6 |
| community.docker / community.general | 5.4.1 / 14.0.1 | `~/.ansible/collections` | 5–6 |
| kubectl | 1.37.3 | `~/.local/bin/kubectl` | 9–16 |
| k3d | 5.9.0 | `~/.local/bin/k3d` | 9–16 |
| Helm | 4.3.2 | `~/.local/bin/helm` | 10–16 |
| ArgoCD CLI | 3.6.3 | `~/.local/bin/argocd` | 13–14 |
| kubectl-argo-rollouts | 1.10.2 | `~/.local/bin/` | 14 |
| OpenBao CLI (`bao`) | 2.7.3 | `~/.local/bin/bao` | 11 |
| Node.js / npm | 22.23.1 / 10.9.8 | `~/.nvm` (default 22) | 17 |
| Wrangler | 4.168.0 | `~/.nvm/.../bin/wrangler` | 17 |
| Nix (nix-portable) | 2.20.6 | `~/.local/bin/nix` | 18 |

> Если в старом терминале остался Node 20: `nvm alias default 22` уже задан; выполните `nvm use 22` или откройте новый терминал.

---

## 3. Аккаунты и доступы

| Что | Зачем | Действие |
|---|---|---|
| GitHub | форк, Actions, GHCR | Форкните репозиторий; создайте PAT с `write:packages`, `read:packages`. |
| GHCR | образы для лаб. 2–3, 9–16 | После первого push сделайте пакет **Public** (иначе `docker pull` даст 401). |
| Cloudflare (бесплатно) | лаб. 17: деплой Worker, KV, secrets | `wrangler login`. В РФ возможны сетевые ограничения — используйте VPN. |
| AWS/GCP/Yandex (есть) | опционально для лаб. 4 | Не обязательны: лаб. 4 проходится на Docker-провайдере локально. |

---

## 4. Соответствие «лабораторная → инструменты»

### Лаб. 1–3 — приложение, Docker, CI
- Python: `uv run` или обычное venv. Для паритета с курсом доступен Python 3.13:
  ```bash
  uv venv --python 3.13 .venv && source .venv/bin/activate
  ```
- Docker/Trivy: `docker build`, `trivy image ...`. **Не используйте Trivy 0.69.4** (скомпрометирован).
- CI — GitHub Actions на бесплатных раннерах.

### Лаб. 4 — Infrastructure as Code (локально)
`releases.hashicorp.com` в этом окружении недоступен, поэтому Terraform заменён на **OpenTofu**
(курс официально поддерживает OpenTofu 1.12+). Команда `terraform` — shim, вызывающий `tofu`:

```bash
terraform version        # => OpenTofu v1.13.10
```

Реестры провайдеров (`registry.opentofu.org`, `registry.terraform.io`) в этом окружении
тоже недоступны, поэтому Docker-провайдер ставится вручную из GitHub-релиза в локальное
filesystem-зеркало (`scripts/lab46-local/terraform-docker/fetch-provider.sh`).

Пример полностью локального сценария — `scripts/lab46-local/terraform-docker/main.tf`
(провайдер `kreuzwerker/docker` v4.7.0):

```bash
cd scripts/lab46-local/terraform-docker
bash fetch-provider.sh
export TF_CLI_CONFIG_FILE="$PWD/.terraformrc"
terraform init && terraform apply -auto-approve
curl -s localhost:8088 | head        # 8080 на хосте занят, используем 8088
terraform destroy -auto-approve
```

> Проверено: `init` → `apply` → nginx отвечает `200` на `:8088` → `destroy` работают.

Pulumi: сервер плагинов `get.pulumi.com` отдаёт 403, поэтому Docker-провайдер Pulumi
придётся ставить вручную; проще пройти лаб. 4 на OpenTofu. Если хотите настоящую
облачную VM — используйте свой аккаунт AWS/GCP/Yandex (опционально).

### Лаб. 5–6 — Ansible (локально)
Готовый каркас — `scripts/lab46-local/`:

- **Вариант A (по умолчанию):** `ansible_connection: local`, деплой в локальный Docker.
  ```bash
  cd scripts/lab46-local && ansible all -m ping
  ```
- **Вариант B:** контейнер-«сервер» с SSH и passwordless sudo:
  ```bash
  cd scripts/lab46-local && ./create-target.sh
  ansible -i inventory.ssh.ini web -m ping
  ```
- Если задачам нужен systemd — локальная VM: `sudo snap install multipass && multipass launch 24.04 -n lab46`.

### Лаб. 7–8 — Логи и метрики (локальный Docker Compose)
Ничего дополнительно ставить не нужно. Стек поднимается через `docker compose`; конфиги-заготовки
лежат в `labs/lab07/loki/config.yml` и `labs/lab8/prometheus/prometheus.yml`.
Порт **8080 на хосте уже занят** (служба с редиректом на `/login`), поэтому публикуйте
приложение на свободном порту, например `8088:8080`. Внутри контейнера/пода сервис
по-прежнему слушает 8080. Останавливайте стек лаб. 6 перед запуском лаб. 7.

### Лаб. 9–16 — Kubernetes в Docker (k3d)
Кластер из 1 server + 2 agents (с закреплением k3s 1.36, если образ доступен):

```bash
k3d cluster create devops \
  --image rancher/k3s:v1.36.1-k3s1 \
  --servers 1 --agents 2 \
  -p "8088:80@loadbalancer" -p "8443:443@loadbalancer"
```

Если образ `v1.36.1-k3s1` недоступен, уберите `--image` (возьмётся версия по умолчанию k3d):

```bash
k3d cluster create devops --servers 1 --agents 2 -p "8088:80@loadbalancer"
kubectl get nodes
```

> `8088`, а не `8080`: порт 8080 на хосте занят другим процессом (см. раздел 7).

Между занятиями останавливайте кластер, чтобы освободить RAM:

```bash
k3d cluster stop devops      # позже: k3d cluster start devops
k3d cluster delete devops    # удалить полностью
```

Инструменты лаб. 10–16: `helm`, `argocd`, `kubectl-argo-rollouts`, `bao` — уже установлены.
Для лаб. 16 используйте **lean-профиль** kube-prometheus-stack (см. раздел 6).

### Лаб. 17 — Edge (Cloudflare Workers)
Wrangler установлен под Node 22 (требование актуальных версий — Node ≥ 22.12):

```bash
wrangler --version          # 4.168.0
wrangler login
wrangler dev --local        # работает без аккаунта
```

Полный зачёт Task 3 и бонус требуют реального деплоя (`wrangler deploy`).

### Лаб. 18 — Воспроизводимые сборки (Nix без root)
Nix поставлен через **nix-portable** (не требует root, хранит данные в `~/.nix-portable`):

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
nix --version               # Nix 2.20.6
nix build
docker load < result        # docker-демон хоста доступен, т.к. Nix работает на хосте
```

Фолбэк — `nix-docker` (Nix в контейнере `nixos/nix:2.34.0`, монтирует cwd и `docker.sock`).
Учтите: при запуске в контейнере созданные файлы могут принадлежать root.

---

## 5. Ресурсы и производительность (15 ГиБ RAM)

- Держите запущенным только один тяжёлый стек: `k3d` **или** Compose-наблюдаемость.
- После лаб. 9–16: `k3d cluster stop devops`.
- Лаб. 16: lean-профиль (без Alertmanager/node-exporter/kube-state-metrics):
  ```bash
  helm install kube-prom prometheus-community/kube-prometheus-stack \
    --set alertmanager.enabled=false \
    --set nodeExporter.enabled=false \
    --set kubeStateMetrics.enabled=false
  ```
- Очистка: `docker system prune`, `docker builder prune`, `nix store gc`.
- Диск: 188 ГБ свободно — достаточно для образов, TSDB Prometheus, Loki и Nix store.

---

## 6. Отличия от «пиннинга» курса

| Курс указывает | Установлено | Причина |
|---|---|---|
| Terraform 1.15 | OpenTofu 1.13.10 (+ `terraform` shim) | `releases.hashicorp.com` недоступен; OpenTofu официально поддерживается |
| Helm 4.1 | 4.3.2 | ближайшая доступная 4.x |
| Kubernetes 1.36 | kubectl 1.37.3 (кластер — по `--image`) | ±1 minor допустим; версию k3s можно закрепить |
| ArgoCD 3.4 | 3.6.3 | ближайшая 3.x (в чарте выбирайте appVersion 3.x) |
| Argo Rollouts 1.8.4 | 1.10.2 | ближайшая; при необходимости закрепите чарт/образ |
| OpenBao 2.5 | 2.7.3 | ближайшая |
| ansible-core 2.21 | 2.22.0 | ближайшая |
| Python 3.13 | 3.13.18 | точно |
| Trivy v0.69.3+ | 0.76.2 | безопасно; **не** 0.69.4 |
| Nix 2.25+ | 2.20.6 (nix-portable) | без root; flakes поддерживаются, но часть новшеств может отличаться |
| Node 18+ | 22.23.1 | требуется свежим Wrangler |

---

## 7. Частые проблемы и подводные камни

**Общее**
- GHCR-пакеты приватны по умолчанию → сделайте **Public**, иначе 401 в лаб. 9/13.
- Trivy v0.69.4 скомпрометирован (CVE-2026-33634) — не использовать.
- **Порт 8080 на хосте занят** (служба с редиректом на `/login`) — используйте `8088` и другой свободный порт; проверяйте `ss -ltn`.
- Стеки лаб. 6 и 7 конфликтуют между собой — не запускайте одновременно.
- Реестры провайдеров Terraform/OpenTofu и сервер плагинов Pulumi недоступны (403) — для лаб. 4 используйте `fetch-provider.sh` (локальное зеркало).
- Студенческие каталоги (`app_python/`, `k8s/`, `ansible/`, `terraform/`, `monitoring/`, `.github/workflows/`) в upstream добавлены в `.gitignore` — коммитьте их в **свой форк**.

**Kubernetes**
- Приватный образ лаб. 2: `k3d image import <image>` и `imagePullPolicy: IfNotPresent`.
- NodePort не виден с хоста без маппинга портов при создании кластера — используйте LoadBalancer/port-forward.
- Ingress в k3d — Traefik: `ingressClassName: traefik` (не nginx).
- Лаб. 10: helper fullname должен «схлопываться» для релиза `lab10-app`; не используйте `helm create`.
- Лаб. 11: dev-сервер OpenBao хранит секреты в памяти (рестарт = потеря); в политиках KV-v2 путь содержит `/data/`.
- Лаб. 12: StorageClass `local-path` = RWO; `Pending` у PVC при `WaitForFirstConsumer` — нормально; env из ConfigMap не перезагружается «на лету», `subPath` не обновляется.
- Лаб. 13: `repoURL` — ваш форк; выбирайте чарт ArgoCD с appVersion 3.x; для приватного репозитория — `argocd-repo-creds`.
- Лаб. 14: под не видит `localhost:9090` — используйте `host.k3d.internal:9090` или Prometheus в кластере; закрепите версии controller/plugin/dashboard.
- Лаб. 15: `volumeClaimTemplates` неизменяемы; `serviceName` должен совпадать с headless-Service.
- Лаб. 16: два селектора (`serviceMonitorSelectorNilUsesHelmValues`, `podMonitorSelectorNilUsesHelmValues`) — частая ошибка; `port` в ServiceMonitor — **именованный** порт Service.

**Edge и Nix**
- `wrangler secret put` требует уже существующий Worker; `request.cf.colo` в `wrangler dev` не определён.
- Лаб. 18: flakes видят только файлы под git — делайте `git add` перед `nix build`; не используйте `nixpkgs-unstable`; `created = "now"` ломает воспроизводимость.

---

## 8. Остановка и очистка

```bash
k3d cluster stop devops                 # остановить кластер
docker compose down                     # остановить compose-стек
docker rm -f lab46-target               # убрать целевой контейнер лаб. 4-6
docker system prune -af && docker builder prune -af
nix store gc                            # почистить Nix store
```

---

## 9. Структура скриптов

```
scripts/
├── setup/
│   ├── lib.sh            # общие функции и версии
│   ├── 00-preflight.sh
│   ├── 10-base.sh
│   ├── 20-iac.sh
│   ├── 30-ansible.sh
│   ├── 40-k8s.sh
│   ├── 50-edge-nix.sh
│   ├── run-all.sh
│   └── verify.sh
└── lab46-local/          # локальная среда для лаб. 4-6
    ├── README.md
    ├── ansible.cfg
    ├── inventory.local.ini
    ├── inventory.ssh.ini
    ├── Dockerfile.target
    ├── create-target.sh
    ├── fetch-provider.sh  # (в terraform-docker/) локальное зеркало провайдера
    └── terraform-docker/main.tf
```

---

## 10. Результат проверки

`verify.sh` на этой машине: **все 22 инструмента найдены** —

```
docker 29.1.3 · compose 2.40.3 · git 2.43 · uv 0.13.10 · trivy 0.76.2 · yq 4.54.3
tofu 1.13.10 · terraform(shim) · pulumi 3.278.0 · tflint 0.66.0
ansible-core 2.22.0 · ansible-lint 26.11.1
kubectl 1.37.3 · k3d 5.9.0 · helm 4.3.2 · argocd 3.6.3 · argo-rollouts 1.10.2 · bao 2.7.3
node 22.23.1 · npm 10.9.8 · wrangler 4.168.0 · nix 2.20.6
```

Дополнительно проверьте создание кластера: `bash scripts/setup/verify.sh --cluster`.
