// Данные учебного дашборда. Источник истины — labs/*.md, здесь краткая карта.
const COURSE = {
  repo: "https://github.com/ecaucsn/DevOps-Core-Course/blob/master",
  phases: [
    { id: "p1", name: "Сервис и поставка", range: "Недели 1–3" },
    { id: "p2", name: "Инфраструктура и автоматизация", range: "Недели 4–6" },
    { id: "p3", name: "Наблюдаемость", range: "Недели 7–8" },
    { id: "p4", name: "Kubernetes", range: "Недели 9–12" },
    { id: "p5", name: "Доставка и масштаб", range: "Недели 13–16" },
    { id: "p6", name: "Бонусные лабораторные", range: "По желанию" }
  ],
  labs: [
    {
      n: 1, week: 1, phase: "p1",
      title: "DevOps Info Service: разработка веб-приложения",
      lecture: 1,
      concepts: ["FastAPI", "HTTP JSON", "конфиг через env", "health-проба", "logging"],
      tasks: [
        "Задача 1: сервис GET / и GET /health",
        "Задача 2: README, requirements (pinned), .gitignore, docs/LAB01.md",
        "Соцактивность GitHub (звёзды/подписки)",
        "Бонус: аналог на компилируемом языке (опционально)"
      ],
      commands: [
        "python3 -m venv venv && source venv/bin/activate",
        "pip install -r requirements.txt",
        "python app.py",
        "curl -s localhost:5000/ | jq ."
      ]
    },
    {
      n: 2, week: 2, phase: "p1",
      title: "Контейнеризация с Docker",
      lecture: 2,
      concepts: ["Dockerfile", "слои и кеш", "non-root UID", "multi-stage", "Trivy", "GHCR"],
      tasks: [
        "Задача 1: Dockerfile + .dockerignore",
        "Задача 2: сборка, запуск, id -u != 0",
        "Задача 3: многоэтапная сборка и сравнение размеров",
        "Задача 4: Trivy (полное + гейтирующее сканирование)",
        "Задача 5: тег и пуш в реестр (не only :latest)"
      ],
      commands: [
        "docker build -t devops-info-service:lab02 ./app_python",
        "docker run -d --rm -p 8088:5000 --name lab02 devops-info-service:lab02",
        "docker run --rm devops-info-service:lab02 id -u",
        "trivy image --severity HIGH,CRITICAL --exit-code 1 devops-info-service:lab02"
      ]
    },
    {
      n: 3, week: 3, phase: "p1",
      title: "Непрерывная интеграция с GitHub Actions",
      lecture: 3,
      concepts: ["CI", "pytest", "ruff", "matrix", "Trivy-гейт", "branch protection"],
      tasks: [
        "Задача 1: workflow на PR (lint + тесты)",
        "Задача 2: сборка образа и Trivy-гейт",
        "Задача 3: публикация образа в GHCR",
        "Задача 4: защита ветки и обязательные проверки"
      ],
      commands: [
        "pytest -q",
        "ruff check .",
        "git push origin lab03"
      ]
    },
    {
      n: 4, week: 4, phase: "p2",
      title: "Инфраструктура как код (Terraform и Pulumi)",
      lecture: 4,
      concepts: ["IaC", "декларативность", "state", "providers", "plan/apply"],
      tasks: [
        "Задача 1: описать инфраструктуру как код",
        "Задача 2: план и применение (локально, Docker-провайдер)",
        "Задача 3: разобрать state и идемпотентность",
        "Бонус: удалённый state / CI"
      ],
      commands: [
        "bash scripts/lab46-local/terraform-docker/fetch-provider.sh",
        "export TF_CLI_CONFIG_FILE=$PWD/.terraformrc",
        "terraform init && terraform plan",
        "terraform apply -auto-approve && terraform destroy"
      ]
    },
    {
      n: 5, week: 5, phase: "p2",
      title: "Основы Ansible",
      lecture: 5,
      concepts: ["инвентарь", "playbook", "роли", "идемпотентность", "Vault"],
      tasks: [
        "Задача 1: инвентарь и первый playbook",
        "Задача 2: идемпотентные задачи",
        "Задача 3: роли и переменные",
        "Задача 4: секреты через Ansible Vault"
      ],
      commands: [
        "cd scripts/lab46-local && ansible all -m ping",
        "ansible-playbook -i inventory.local.ini site.yml",
        "ansible-vault encrypt_string 'secret' --name 'db_password'"
      ]
    },
    {
      n: 6, week: 6, phase: "p2",
      title: "Продвинутый Ansible и непрерывное развёртывание",
      lecture: 6,
      concepts: ["Compose v2", "handlers", "templates", "CD из CI", "OIDC"],
      tasks: [
        "Задача 1: деплой через community.docker",
        "Задача 2: шаблоны и handlers",
        "Задача 3: CD-пайплайн",
        "Задача 4 (бонус): OIDC вместо долгоживущих ключей"
      ],
      commands: [
        "ansible-lint .",
        "docker compose up -d",
        "docker compose ps"
      ]
    },
    {
      n: 7, week: 7, phase: "p3",
      title: "Наблюдаемость и логирование (Loki)",
      lecture: 7,
      concepts: ["Loki", "Grafana Alloy", "LogQL", "структурированные логи", "Grafana"],
      tasks: [
        "Задача 1: поднять стек Loki + Alloy + Grafana",
        "Задача 2: настроить сбор логов приложения",
        "Задача 3: запросы LogQL и дашборд"
      ],
      commands: [
        "docker compose up -d",
        "curl -s localhost:3100/ready",
        "docker compose logs -f alloy"
      ]
    },
    {
      n: 8, week: 8, phase: "p3",
      title: "Метрики и мониторинг (Prometheus)",
      lecture: 8,
      concepts: ["Prometheus", "PromQL", "RED/USE", "/metrics", "Grafana"],
      tasks: [
        "Задача 1: эндпоинт /metrics и инструментирование",
        "Задача 2: Prometheus + Grafana",
        "Задача 3: PromQL-запросы (RED/USE)",
        "Задача 4: алерты"
      ],
      commands: [
        "docker compose up -d",
        "curl -s localhost:8088/metrics | head",
        "curl -s localhost:9090/-/ready"
      ]
    },
    {
      n: 9, week: 9, phase: "p4",
      title: "Основы Kubernetes на k3d",
      lecture: 9,
      concepts: ["Pod", "Deployment", "Service", "probes", "k3d", "kube-DNS"],
      tasks: [
        "Задача 1: кластер k3d (1 server, 2 agents)",
        "Задача 2: Deployment + Service вашего сервиса",
        "Задача 3: пробы /health",
        "Задача 4: подключить второй сервис echo"
      ],
      commands: [
        "k3d cluster create devops --servers 1 --agents 2 -p '8088:80@loadbalancer'",
        "kubectl apply -f k8s/",
        "kubectl get pods,svc -o wide",
        "kubectl port-forward svc/web 8080:8080"
      ]
    },
    {
      n: 10, week: 10, phase: "p4",
      title: "Пакетный менеджер Helm",
      lecture: 10,
      concepts: ["чарт", "values", "templates", "hooks", "OCI"],
      tasks: [
        "Задача 1: свой чарт Helm 4",
        "Задача 2: окружения dev/staging/prod",
        "Задача 3: хук жизненного цикла",
        "Бонус: публикация в GHCR OCI"
      ],
      commands: [
        "helm lint k8s/lab10-app",
        "helm template lab10-app k8s/lab10-app",
        "helm install lab10-app k8s/lab10-app -f values.yaml"
      ]
    },
    {
      n: 11, week: 11, phase: "p4",
      title: "Секреты Kubernetes и OpenBao",
      lecture: 11,
      concepts: ["K8s Secrets", "OpenBao", "KV-v2", "политики", "ESO"],
      tasks: [
        "Задача 1: K8s Secret",
        "Задача 2: OpenBao dev-сервер и секреты",
        "Задача 3: интеграция с приложением",
        "Бонус: External Secrets Operator"
      ],
      commands: [
        "bao server -dev -dev-root-token-id=root",
        "export BAO_ADDR=http://127.0.0.1:8200",
        "bao kv put secret/app password=s3cr3t",
        "kubectl create secret generic app-env --from-literal=KEY=value"
      ]
    },
    {
      n: 12, week: 12, phase: "p4",
      title: "ConfigMaps и постоянные тома",
      lecture: 12,
      concepts: ["ConfigMap", "PV/PVC", "StorageClass", "hot-reload", "subPath"],
      tasks: [
        "Задача 1: ConfigMap и монтирование",
        "Задача 2: PVC и StorageClass local-path",
        "Задача 3: сохранить состояние между рестартами",
        "Бонус: hot-reload через Reloader"
      ],
      commands: [
        "kubectl apply -f k8s/",
        "kubectl get pvc,pv",
        "kubectl exec deploy/web -- cat /data/counter"
      ]
    },
    {
      n: 13, week: 13, phase: "p5",
      title: "GitOps с ArgoCD",
      lecture: 13,
      concepts: ["GitOps", "ArgoCD", "Application", "ApplicationSet", "sync"],
      tasks: [
        "Задача 1: установить ArgoCD 3.x",
        "Задача 2: Application на ваш форк",
        "Задача 3: ApplicationSet для 3 сервисов",
        "Задача 4: автосинк и самовосстановление"
      ],
      commands: [
        "kubectl apply -f argocd/",
        "argocd login localhost:8080 --insecure",
        "argocd app sync web",
        "argocd app get web"
      ]
    },
    {
      n: 14, week: 14, phase: "p5",
      title: "Прогрессивная доставка с Argo Rollouts",
      lecture: 14,
      concepts: ["canary", "blue-green", "AnalysisTemplate", "promote", "undo"],
      tasks: [
        "Задача 1: установить Argo Rollouts",
        "Задача 2: canary-стратегия",
        "Задача 3: blue-green-переключение",
        "Бонус: AnalysisTemplate с Prometheus"
      ],
      commands: [
        "kubectl argo rollouts get rollout web --watch",
        "kubectl argo rollouts promote web",
        "kubectl argo rollouts undo web"
      ]
    },
    {
      n: 15, week: 15, phase: "p5",
      title: "StatefulSets и постоянное хранилище",
      lecture: 15,
      concepts: ["StatefulSet", "headless Service", "volumeClaimTemplates", "операторы"],
      tasks: [
        "Задача 1: headless Service + StatefulSet",
        "Задача 2: volumeClaimTemplates",
        "Задача 3: стабильные сетевые имена",
        "Бонус: оператор (CloudNativePG/Strimzi и т.п.)"
      ],
      commands: [
        "kubectl apply -f k8s/statefulset.yaml",
        "kubectl get sts,pvc,pods",
        "kubectl exec web-0 -- nslookup web-1.web"
      ]
    },
    {
      n: 16, week: 16, phase: "p5",
      title: "Мониторинг Kubernetes и init-контейнеры",
      lecture: 16,
      concepts: ["kube-prometheus-stack", "ServiceMonitor", "init containers", "lean-профиль"],
      tasks: [
        "Задача 1: kube-prometheus-stack (lean)",
        "Задача 2: ServiceMonitor для приложения",
        "Задача 3: init-контейнер",
        "Задача 4: sidecar и его метрики"
      ],
      commands: [
        "helm install kube-prom prometheus-community/kube-prometheus-stack --set alertmanager.enabled=false",
        "kubectl get servicemonitor,podmonitor",
        "kubectl get pods -n monitoring"
      ]
    },
    {
      n: 17, week: 17, phase: "p6",
      title: "Развёртывание на периферии (Cloudflare Workers)",
      lecture: 16,
      concepts: ["edge", "V8 isolates", "Wrangler", "KV", "secrets"],
      tasks: [
        "Задача 1: Worker на wrangler",
        "Задача 2: KV и секреты",
        "Задача 3: реальный деплой и rollback",
        "Бонус: сравнение с k8s по латентности"
      ],
      commands: [
        "wrangler login",
        "wrangler dev --local",
        "wrangler deploy",
        "wrangler deployments list"
      ]
    },
    {
      n: 18, week: 18, phase: "p6",
      title: "Воспроизводимые сборки с Nix",
      lecture: 16,
      concepts: ["Nix", "flakes", "детерминизм", "dockerTools", "reproducibility"],
      tasks: [
        "Задача 1: flake и сборка приложения",
        "Задача 2: воспроизводимый docker-образ",
        "Задача 3: сравнить с Dockerfile-сборкой",
        "Задача 4: фиксированные входы (lock)"
      ],
      commands: [
        "export NIX_CONFIG='experimental-features = nix-command flakes'",
        "nix build",
        "docker load < result",
        "nix flake metadata"
      ]
    }
  ]
};
