# Лабораторная 4 — Инфраструктура как код (Terraform & Pulumi)

![difficulty](https://img.shields.io/badge/difficulty-beginner-success)
![topic](https://img.shields.io/badge/topic-Infrastructure%20as%20Code-blue)
![points](https://img.shields.io/badge/points-10%2B2-orange)
![tech](https://img.shields.io/badge/tech-Terraform%20%7C%20Pulumi-informational)

> **Цель:** Провизьонировать *одну и ту же* небольшую виртуальную машину дважды — один раз на **Terraform** HCL, один раз на **Pulumi** Python — и прочувствовать компромиссы на практике.
> **Результат сдачи:** PR из `lab04` с `terraform/`, `pulumi/`, `docs/LAB04.md` и (бонус) `.github/workflows/terraform-ci.yml`.

---

## Обзор

В этой лабораторной работе вы отработаете:
- Жизненный цикл **`init → plan → apply → destroy`** (и чтение плана как diff)
- Написание четырёх примитивов HCL — `provider`, `resource`, `variable`, `output` — и одного источника `data`
- Воссоздание той же инфраструктуры на Pulumi Python (реальные циклы, реальные типы, реальные импорты)
- **Управление state** — что лежит в `terraform.tfstate`, почему это секрет, почему важна блокировка

> ⚠️ **Область:** одна облачная VM (или одна замена на docker-провайдере — см. примечание ниже). Без Kubernetes, без развёртывания приложения. Лабораторная 5 подключится по SSH к тому, что вы здесь создадите.

**Облако или docker-провайдер?** Выберите облако с бесплатным тарифом (рекомендуется — это настоящий навык), но если вы не можете открыть аккаунт, требующий карту, провайдер `kreuzwerker/docker` прогоняет *точно такой же жизненный цикл* локально против контейнера. **Перекрёстная ссылка на лабораторную 5 для пользователей docker:** у контейнера нет sshd; лабораторная 5 будет использовать `ansible_connection: community.docker.docker` (или запускать Ansible с `connection: local` против `docker exec`) вместо SSH — те же роли, другой плагин подключения. Любой путь даёт полные баллы; задокументируйте, какой выбрали.

---

## Состояние проекта

**У вас должно быть из предыдущих лабораторных:**
- Лабораторная 1: `app_python/` (и, возможно, `app_go/`) — сервис, который вы запустите на VM
- Лабораторная 2: многоэтапный Docker-образ, запушенный в GHCR
- Лабораторная 3: GitHub Actions, собирающий/пушующий на каждом PR

**Эта лабораторная добавляет:**
- `terraform/` — HCL, который вы написали сами, провизьонирующий **одну VM** (или один контейнер)
- `pulumi/` — Python, воссоздающий *ту же* инфраструктуру
- `docs/LAB04.md` — ваши заметки о прогоне + сравнение Terraform и Pulumi

К лабораторной 5 вы подключаетесь по SSH к этому хосту и конфигурируете его через Ansible. К лабораторной 9 вы замените его на k3d, но образ мышления IaC остаётся тем же.

---

## Технологический стек и версии

| Инструмент | Версия | Примечания |
|------|---------|-------|
| **Terraform** | **1.15.3** | BSL-1.1 с **2023-08-10**. Закрепляйте на `>= 1.15.0`. |
| **OpenTofu** | **1.12.0** | MPL-2.0, Linux Foundation. 1:1 замена — `tofu` работает для каждой команды ниже. |
| **Pulumi** | **3.243.0** | Apache-2.0 повсюду. |
| **AWS provider** | `~> 5.0` | Самый документированный облачный путь. |
| **GCP provider** | `~> 6.0` | Альтернатива. |
| **Yandex provider** | `~> 0.115` | Дружелюбен к России, изначально без карты. |
| **Docker provider** | `kreuzwerker/docker ~> 3.0` | Бесплатная локальная замена, если нет облачного аккаунта. |

> **Замечание об OpenTofu:** перелицензирование BSL 10 августа 2023 сделало OpenTofu необходимым; сегодняшний 1.12.0 запускает идентичный HCL против того же registry. Проверяющий принимает любой CLI.

---

## Подготовка

```bash
terraform -version   # или: tofu -version
pulumi version

# Сгенерируйте пару SSH-ключей для VM, если её у вас нет
ssh-keygen -t ed25519 -f ~/.ssh/lab04 -C "lab04@$(hostname)"
chmod 600 ~/.ssh/lab04
cat  ~/.ssh/lab04.pub          # именно это ваш IaC внедрит
```

Выберите **одну** цель и придерживайтесь её для обоих инструментов:

| Цель | Наименьшая бесплатная единица | Провайдер |
|--------|---------------------|----------|
| **AWS** | `t3.micro` (12 мес. бесплатно) | `hashicorp/aws` |
| **GCP** | `e2-micro` (зона always-free) | `hashicorp/google` |
| **Yandex** | 2 vCPU @ 20%, 1 ГБ | `yandex-cloud/yandex` |
| **DigitalOcean** | кредит студента `$200` | `digitalocean/digitalocean` |
| **Docker (локально)** | контейнер | `kreuzwerker/docker` |

> **Никаких учётных данных в коде.** Используйте переменные окружения (`AWS_ACCESS_KEY_ID`, `GOOGLE_APPLICATION_CREDENTIALS`, `YC_TOKEN`, …) или общий профиль. Никогда не встраивайте их в `provider {}`.

Структура каталогов (файлы вы заполните сами):

```
terraform/
├── main.tf          # провайдер + ресурсы
├── variables.tf     # входные данные
├── outputs.tf       # публичный IP, команда ssh
├── terraform.tfvars # значения — В GITIGNORE
├── .gitignore
└── README.md

pulumi/
├── __main__.py
├── Pulumi.yaml
├── Pulumi.dev.yaml  # В GITIGNORE, если содержит секреты
├── requirements.txt
└── .gitignore

docs/LAB04.md
```

---

## Задача 1 — Terraform VM (4 балла)

**Цель:** доступная VM, написанная на вашем собственном HCL, с чистой гигиеной state.

### 1.1 — Напишите строительные блоки HCL

Лекция 4 рассказала, что у HCL есть шесть примитивов, которые вы встретите сегодня: `terraform {}`, `provider`, `variable`, `data`, `resource`, `output`. В этой задаче вы их и пишете.

`ВАША ЗАДАЧА`: создайте `terraform/main.tf`, покрывающий **всё** следующее. Не копируйте с Stack Overflow — именно так секреты попадают в tfstate.

Требуемая **форма** HCL (заполните каждый `___` и каждый комментарий `# ВАША ЗАДАЧА:` реальными значениями; **не** копируйте полное решение откуда-либо):

```hcl
# main.tf
terraform {
  required_version = ">= ___"                          # ВАША ЗАДАЧА: закрепите минимальную версию TF/OpenTofu
  required_providers {
    ___ = {                                             # ВАША ЗАДАЧА: локальное имя провайдера
      source  = "___/___"                               # ВАША ЗАДАЧА: источник в registry
      version = "~> ___"                                # ВАША ЗАДАЧА: закрепите мажор
    }
  }
}

provider "___" {
  region = var.region    # форма AWS; GCP нужен `project` + `region` или `zone`,
                         # Yandex нужен `zone`, kreuzwerker/docker не принимает region.
                         # Адаптируйте под выбранного провайдера — см. блок Resources.
  # ⛔ никаких встроенных учётных данных (access_key/secret_key, тело JSON SA-ключа и т.п.) — только env vars или профиль
}

# ВАША ЗАДАЧА: источник данных, возвращающий ID последнего образа Ubuntu 24.04
# (Подсказка по облакам: aws_ami / google_compute_image / yandex_compute_image).
# Жёстко заданные AMI ID устаревают за месяцы — поэтому это источник данных.
data "___" "ubuntu" {
  # фильтры / owners / family — ВАША ЗАДАЧА
}

# ВАША ЗАДАЧА: security group / firewall с именем "lab4-sg", разрешающая:
#   - входящий 22/tcp только из var.my_ip/32        (НИКОГДА не 0.0.0.0/0 для SSH)
#   - входящие 80/tcp и 5000/tcp откуда угодно      (порт вашего приложения)
#   - исходящий весь
# Помечена тегами { Name = "lab4-sg", Env = "lab4" }.
resource "___" "lab" {
  # name, description, блоки ingress, блок egress, tags — ВАША ЗАДАЧА
}

# ВАША ЗАДАЧА: ресурс SSH-ключа — публичный ключ из var.ssh_public_key.
resource "___" "lab" {
  # name + public_key — ВАША ЗАДАЧА
}

# ВАША ЗАДАЧА: сама VM. Обязательная связка:
#   - ami / image  ← из вашего источника данных выше
#   - instance_type / machine_type ← var.instance_type
#   - key_name / metadata.ssh-keys ← ваш ресурс ключа
#   - vpc_security_group_ids / network_interface ← ваша SG/firewall
#   - user_data: однострочник, который выполняется при первой загрузке и пишет
#       "hello from $(hostname)" в /var/log/lab4-boot.log
#   - tags: { Name = "lab4-web", Env = "lab4" }
resource "___" "web" {
  # ВАША ЗАДАЧА
}
```

```hcl
# variables.tf
# ВАША ЗАДАЧА: объявите 4 переменные — region, instance_type, my_ip, ssh_public_key.
# Используйте реальные типы HCL (string / number / bool / list). Напоминание: `int` НЕ
# валидный тип HCL — используйте `number`. Пометьте ssh_public_key sensitive = true.
```

```hcl
# outputs.tf
output "public_ip" {
  value = ___                                           # ВАША ЗАДАЧА: ссылка на ресурс
}

output "ssh_command" {
  value = ___                                           # ВАША ЗАДАЧА: строка, готовая к копипасту
                                                        # например, "ssh -i ~/.ssh/lab04 ubuntu@<ip>"
}
```

```gitignore
# terraform/.gitignore
# ВАША ЗАДАЧА: игнорируйте всё, что содержит state, секреты или локальные загрузки.
# Подсказка: tfstate, tfstate.backup, каталог .terraform/, *.tfvars, *.pem, *.key.
# ОБЯЗАТЕЛЬНО коммитьте .terraform.lock.hcl — он закрепляет версии провайдеров для воспроизводимости.
```

### 1.2 — Прогоните жизненный цикл (и прочитайте план)

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan -out=tfplan      # ПРОЧИТАЙТЕ ЭТО. + create / ~ update / - destroy / -/+ replace
terraform apply tfplan
```

`ВАША ЗАДАЧА`: после `apply` **подключитесь по SSH и докажите, что user_data выполнился**:

```bash
ssh -i ~/.ssh/lab04 ubuntu@<public_ip> "cat /var/log/lab4-boot.log; hostname"
```

(Если вы выбрали замену на docker-провайдере: используйте `docker exec` и `curl` на порт приложения — эталонная сдача показывает эквивалентный снимок.)

### 1.3 — Управление state — фокус на режимах отказа

Именно здесь и студенты, и профессионалы теряют часы. Слайды 15–17 лекции 4 — это теория; здесь — практика.

`ВАША ЗАДАЧА`: в `docs/LAB04.md` вставьте вывод `terraform state list` и ответьте **всего в 3 предложениях**:

1. Что содержит `terraform.tfstate`, что делает его секретом? (Посмотрите на него. Не коммитьте его.)
2. Почему локальный state катастрофичен для команды из двух инженеров?
3. Что делает `.terraform.lock.hcl`, и почему вы коммитите *его*, но никогда tfstate?

### 1.4 — Доказательство выполнения

**Вставьте в `docs/LAB04.md`:**

- Вывод `terraform plan` (очищенный — уберите ARN/ID аккаунтов)
- Строку сводки `terraform apply` (`N to add, M to change, K to destroy`)
- Вывод `terraform state list`
- Сессию SSH, показывающую `cat /var/log/lab4-boot.log` и `hostname`
- Вывод `find terraform -maxdepth 2 -type f | sort`, доказывающий, что `.tfstate` **не** в дереве

---

## Задача 2 — Pulumi VM (4 балла)

**Цель:** воссоздать *ту же* инфраструктуру на Pulumi Python, чтобы вы могли её сравнить.

### 2.1 — Уничтожьте или сохраните Terraform VM

`ВАША ЗАДАЧА`: выберите один путь и задокументируйте его:

- **Путь A** (рекомендуется): сначала `terraform destroy`, соберите Pulumi VM, оставьте её для лабораторной 5. Вставьте вывод `destroy`.
- **Путь B**: оставьте Terraform VM для лабораторной 5, соберите Pulumi VM, сделайте `pulumi destroy` после скриншота. Не оставляйте две работающие VM без документации — именно так в 3 часа ночи срабатывают оповещения о биллинге.

### 2.2 — Напишите программу Pulumi

```python
# pulumi/__main__.py
# ВАША ЗАДАЧА: импорты — pulumi + ваш пакет провайдера (pulumi_aws / pulumi_gcp / …)
import ___
import ___ as ___

# ВАША ЗАДАЧА: прочитайте те же три входных значения, что вы использовали в TF, через pulumi.Config().
# pulumi config set myIp $(curl -s ifconfig.me)
# pulumi config set sshPublicKey "$(cat ~/.ssh/lab04.pub)"
# pulumi config set instanceType t3.micro
cfg = ___
my_ip       = ___
ssh_pub     = ___
instance_ty = ___

# ВАША ЗАДАЧА: тот же поиск Ubuntu, что в вашем источнике данных TF,
# но с использованием функции get_<image> провайдера (например, aws.ec2.get_ami(...)).
ubuntu = ___

# ВАША ЗАДАЧА: security group / firewall — те же правила, что в TF.
sg = ___

# ВАША ЗАДАЧА: пара ключей — тот же публичный ключ.
key = ___

# ВАША ЗАДАЧА: сама инстанция. Передайте ту же строку user_data.
web = ___

# ВАША ЗАДАЧА: два экспорта — public_ip и готовая к вставке команда ssh.
pulumi.export("public_ip", ___)
pulumi.export("ssh_command", ___)         # подсказка: .apply(lambda ip: f"ssh ...")
```

```ini
# pulumi/Pulumi.yaml
# ВАША ЗАДАЧА: имя проекта lab04, runtime python, описание одной строкой.
```

```text
# pulumi/requirements.txt
# ВАША ЗАДАЧА: закрепите pulumi >= 3.243 и ваш пакет провайдера
# (pulumi-aws / pulumi-gcp / pulumi-yandex / pulumi-docker).
```

```gitignore
# pulumi/.gitignore
# ВАША ЗАДАЧА: игнорируйте venv/, __pycache__/ и любой Pulumi.<stack>.yaml, который
# содержит секреты в открытом виде. Само имя стека (Pulumi.dev.yaml) может быть
# закоммичено, если все значения зашифрованы через `pulumi config set --secret`.
```

### 2.3 — Прогоните жизненный цикл

```bash
pulumi login --local                             # или `pulumi login` для Pulumi Cloud
pulumi stack init dev
pulumi config set aws:region eu-central-1        # адаптируйте под провайдера
pulumi config set myIp $(curl -s ifconfig.me)
pulumi config set --secret sshPublicKey "$(cat ~/.ssh/lab04.pub)"

pulumi preview                                   # ≈ terraform plan
pulumi up --yes
# ... подключитесь по ssh и проверьте ...
pulumi destroy --yes                             # если Путь B выше, или перед лабораторной 5 при Пути A
```

### 2.4 — Доказательство выполнения

**Вставьте в `docs/LAB04.md`:**

- Вывод `pulumi preview` (очищенный)
- Строку сводки `pulumi up`
- Сессию SSH против Pulumi VM (или эквивалент на docker-замене)
- Либо доказательство `terraform destroy` (Путь A), либо доказательство `pulumi destroy` (Путь B)

### 2.5 — Сравнение (в этом и смысл делать оба)

`ВАША ЗАДАЧА`: в `docs/LAB04.md` напишите 3–5 предложений для каждого из:

1. **Читаемость** — какой файл было легче просмотреть через неделю?
2. **Логика и циклы** — представьте развёртывание той же VM × `["dev","staging","prod"]`. Какой инструмент показался вам естественнее для этого?
3. **Отладка** — когда ваш `apply`/`up` падал, сообщение об ошибке какого инструмента быстрее указывало на исправление?
4. **State + секреты** — куда каждый инструмент кладёт state? Какой шифрует секреты по умолчанию?
5. **Когда вы бы выбрали каждый** — один конкретный сценарий на инструмент, взятый из вашего собственного опыта на этой неделе.

---

## Задача 3 — Документация (2 балла)

`docs/LAB04.md` должен содержать, по порядку:

1. **Провайдер и цель** — какое облако (или docker-замена), какой регион/зона, размер инстанса и однострочная заметка о стоимости (должно быть `$0`).
2. **Реализация Terraform** — использованная версия, структура файлов, ответ про управление state в 3 предложениях из 1.3, очищенный вывод жизненного цикла, доказательство SSH.
3. **Реализация Pulumi** — язык + версия, вывод жизненного цикла, доказательство SSH.
4. **Terraform против Pulumi** — сравнение из 5 пунктов из 2.5.
5. **Подготовка к лабораторной 5 и очистка** — какая VM (если есть) остаётся живой, или как лабораторная 5 воссоздаст одну из вашего IaC. Плюс доказательство `destroy` для всего, что вы уничтожили.

> Весь вывод терминала должен быть очищен: без полных ID аккаунтов, без ключей доступа, без API-токенов. Помечайте всё реконструированное `(illustrative)`.

---

## Бонусная задача — CI/CD для IaC + удалённый state (2 балла)

### Часть 1 — Валидация в GitHub Actions (1 балл)

`ВАША ЗАДАЧА`: создайте `.github/workflows/terraform-ci.yml`, который запускается на PR, затрагивающих `terraform/**`, и выполняет `fmt -check -recursive`, `init -backend=false`, `validate` и `tflint`. Используйте только **first-party** actions — `hashicorp/setup-terraform` (или `opentofu/setup-opentofu`) и `terraform-linters/setup-tflint`. Без долгоживущих облачных учётных данных: `-backend=false` пропускает state.

Скелет — заполните пропуски:

```yaml
# .github/workflows/terraform-ci.yml
name: terraform-ci
on:
  pull_request:
    paths:
      - 'terraform/**'
      - '.github/workflows/terraform-ci.yml'

jobs:
  validate:
    runs-on: ubuntu-24.04
    defaults:
      run: { working-directory: terraform }
    steps:
      - uses: actions/checkout@v4
      - uses: ___                                       # ВАША ЗАДАЧА: action setup-terraform + закрепление версии
        with:
          terraform_version: "___"                      # ВАША ЗАДАЧА: версия из таблицы выше
      # ВАША ЗАДАЧА: 4 шага — fmt -check -recursive, init -backend=false, validate, tflint.
      # tflint нужен собственный setup action; добавьте минимальный terraform/.tflint.hcl.
```

**Докажите это:**
- Откройте PR, затрагивающий `terraform/` — workflow запускается и остаётся зелёным.
- Запушьте коммит, нарушающий `fmt`, поверх — workflow становится **красным** на шаге `fmt -check`. Скриншот или вставьте падающий лог.
- Затроньте файл вне `terraform/**` — workflow **не** запускается.

### Часть 2 — Миграция на удалённый, заблокированный state (1 балл)

`ВАША ЗАДАЧА`:

1. Создайте бакет для state: S3 с **версионированием + шифрованием**, или GCS с версионированием, или Yandex Object Storage. Вручную или крошечной отдельной конфигурацией Terraform — задокументируйте, чем именно.
2. Добавьте блок `backend "s3"` / `backend "gcs"` в вашу конфигурацию `terraform/`:
   - Для S3 используйте `use_lockfile = true` (нативная блокировка state в TF 1.10+ — больше не нужна таблица DynamoDB).
   - Для GCS блокировка нативная и автоматическая.
   - **Всегда** задавайте `encrypt = true`.
3. Выполните `terraform init -migrate-state` и подтвердите, что локальный `terraform.tfstate` переехал в бакет.
4. Снова выполните `terraform plan` — он должен сообщить **No changes** (доказывает, что state мигрировал чисто, а не ре-импортирован).
5. В `docs/LAB04.md` объясните в 2–3 предложениях, **почему блокировка мешает двум инженерам повредить state** и как выглядит режим отказа без неё.

---

## Как сдавать

```bash
git switch -c lab04
git add terraform/ pulumi/ docs/LAB04.md
git add .github/workflows/terraform-ci.yml      # только бонус
git commit -m "feat(lab04): IaC with Terraform + Pulumi"
git push -u origin lab04
```

Откройте **два** PR:

- `your-fork:lab04` → `course-repo:master` *(проверяется)*
- `your-fork:lab04` → `your-fork:master`

Чек-лист PR:

```text
- [ ] terraform/ провизьонирует VM от начала до конца; SSH доказан
- [ ] pulumi/ воссоздаёт ту же инфраструктуру; SSH доказан
- [ ] В diff нет *.tfstate, *.tfvars, .terraform/ или файла секретного стека Pulumi
- [ ] .terraform.lock.hcl ЗАКОММИЧЕН
- [ ] docs/LAB04.md содержит все 5 разделов + сравнение TF и Pulumi
- [ ] Оставлена работающей максимум ОДНА VM, и она названа в docs (для лабораторной 5)
- [ ] Бонус (опционально): terraform-ci.yml доказан зелёным+красным; state мигрирован удалённо
```

---

## Критерии приёмки

### Задача 1 — Terraform (4 балла)
- ✅ Провайдер выбран, аутентификация через env/профиль (без встроенных учётных данных)
- ✅ Источник `data` для образа Ubuntu (не жёстко заданный AMI/ID)
- ✅ Security group / firewall ограничивает **SSH 22 только вашим IP/32**
- ✅ Присутствуют все шесть примитивов: `terraform{}`, `provider`, `variable`, `resource`, `data`, `output`
- ✅ `user_data` выполняется при первой загрузке и пишет в `/var/log/lab4-boot.log`
- ✅ Сессия SSH в `docs/LAB04.md` показывает строку лога загрузки + имя хоста
- ✅ `.gitignore` корректен: tfstate игнорируется, `.terraform.lock.hcl` закоммичен
- ✅ Присутствует ответ про управление state в 3 предложениях

### Задача 2 — Pulumi (4 балла)
- ✅ Та же инфраструктура воссоздана на Pulumi Python (или TS/Go/Java — рекомендуется Python)
- ✅ `pulumi preview` + `pulumi up` успешны; SSH доказан
- ✅ Оставлена работающей максимум одна из двух VM, и это задокументировано
- ✅ Сравнение TF и Pulumi из 5 пунктов

### Задача 3 — Документация (2 балла)
- ✅ Все 5 разделов в `docs/LAB04.md`
- ✅ Выводы очищены; включено доказательство очистки

### Бонус (2 балла)
- ✅ `terraform-ci.yml` запускает `fmt`/`init`/`validate`/`tflint`, привязан к `terraform/**`, доказан зелёным + красным — **1 балл**
- ✅ Удалённый, зашифрованный, **заблокированный** backend; миграция подтверждена; обоснована блокировка — **1 балл**

---

## Рубрика

| Задача | Баллы | Критерии |
|------|-------:|----------|
| **Задача 1** — Terraform VM | **4** | Работающая инфраструктура, источник данных, ограниченный SSH, переменные/выводы, чистая гигиена state |
| **Задача 2** — Pulumi VM | **4** | Та же инфраструктура на Pulumi, SSH доказан, сравнение написано |
| **Задача 3** — Документация | **2** | Все 5 разделов, очищенный вывод, доказательство очистки |
| **Бонус** — CI для IaC | **1** | Workflow fmt/validate/lint с фильтрацией путей, доказательство зелёного и красного |
| **Бонус** — Удалённый state | **1** | Зашифрованный + заблокированный backend, миграция доказана, обоснование объяснено |
| **Итого** | **10 + 2** | 10 основных + 2 бонусных |

**Не подлежит обсуждению:** только бесплатный тариф · никаких секретов или state в Git · доказательство SSH обязательно · максимум одна VM оставлена для лабораторной 5.

---

## Ресурсы

<details>
<summary>📚 Terraform / OpenTofu</summary>

- [Terraform docs](https://developer.hashicorp.com/terraform/docs) · [Registry](https://registry.terraform.io/)
- [OpenTofu](https://opentofu.org) — drop-in форк; руководство по миграции
- [S3 backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3) · [State locking](https://developer.hashicorp.com/terraform/language/state/locking) · [`terraform import`](https://developer.hashicorp.com/terraform/cli/import)
- [tflint](https://github.com/terraform-linters/tflint)
- *Terraform: Up & Running* — Brikman (4e, 2024 — охватывает OpenTofu)

</details>

<details>
<summary>📦 Pulumi</summary>

- [Pulumi docs](https://www.pulumi.com/docs/) · [Registry](https://www.pulumi.com/registry/)
- [Pulumi vs Terraform](https://www.pulumi.com/docs/concepts/vs/terraform/) · [Secrets](https://www.pulumi.com/docs/concepts/secrets/)

</details>

<details>
<summary>☁️ Краткие справочники по провайдерам</summary>

- **AWS** — [provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs); аутентификация через `AWS_ACCESS_KEY_ID` / `~/.aws/credentials`. ID владельца Ubuntu: `099720109477`.
- **GCP** — [provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs); аутентификация через `gcloud auth application-default login`. Включите Compute Engine API. SSH-ключ в `metadata = { ssh-keys = "ubuntu:${var.ssh_public_key}" }` инстанса.
- **Yandex** — [provider docs](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs); JSON-ключ сервисного аккаунта. Форма бесплатного тарифа: `standard-v3`, `core_fraction = 20`, 1 ГБ RAM.
- **Docker-замена** — `kreuzwerker/docker ~> 3.0`; `docker_image` + `docker_container`. Без SSH; `docker exec` + curl на опубликованный порт.

</details>

<details>
<summary>⚠️ Частые ошибки (из реальных прогонов)</summary>

- **`type = int` — невалидный HCL.** Типы переменных — `string`, `number`, `bool`, `list`, `map`, `set`, `object`, `tuple`, `any`. `int` провалит `terraform validate` с «Invalid type specification» — используйте `number`.
- **Закоммиченный `terraform.tfstate`.** Содержит ID ресурсов, приватные IP, иногда секреты в открытом виде, а конфликты слияния в JSON *невосстановимы*. Строка 1 в `.gitignore`.
- **Забытый `.terraform.lock.hcl`.** Вот **его ВЫ КОММИТИТЕ** — он закрепляет хеши провайдеров, чтобы `init` коллеги разрешался в тот же патч `aws ~> 5.x`, что использовали вы. Без него два инженера могут применить с едва различимыми версиями провайдеров и получить разную инфраструктуру.
- **Учётные данные в `provider {}`.** Code Spaces (2014) был удалён за 12 часов из-за точно этого шаблона. Env vars или общий профиль, никогда не встраивайте. Не кладите их и в `.tfvars` — это ещё один файл, который студенты коммитят по ошибке.
- **Egress по умолчанию запрещён в новой AWS security group.** У ресурса Terraform `aws_security_group` *нет неявного egress*, в отличие от консоли AWS — вы должны сами написать блок `egress`, иначе VM не может выйти в интернет для `apt`, user_data зависает, а `apply` «успешно» завершается со сломанным хостом.
- **Расчёт на VPC по умолчанию.** Он существует в аккаунтах AWS первого дня, но новые организации удаляют его для соответствия требованиям. Либо найдите его через `data "aws_vpc" "default" { default = true }`, либо создайте свой — никогда не предполагайте.
- **SSH нараспашку.** `0.0.0.0/0` на порту 22 = ваша VM в ботнете через несколько часов. Только `var.my_ip/32`. (`curl -s ifconfig.me`, чтобы найти свой IP.)
- **Жёстко заданный AMI ID.** `ami-0c55b159cbfafe1f0` был AMI Ubuntu 22.04 в eu-central-1 *однажды*. AMI меняются, когда Canonical выпускает патчи; жёстко заданные ID устаревают за месяцы. Используйте фильтр `data "aws_ami"` по шаблону имени.
- **Два одновременных `apply` с локальным state.** JSON state записывается наполовину, Terraform не может его разобрать, восстановление — ручное редактирование, которое само по себе запрещено. Именно поэтому существует бонусная задача.

</details>

---

## Взгляд вперёд

| Лабораторная | Что она делает с вашей VM из лабораторной 4 |
|---:|---|
| 5 | Роли Ansible подключаются по SSH и устанавливают Docker + ваше приложение из лабораторных 1–3 |
| 6 | Блоки/спасение Ansible, теги, развёртывание Compose через тот же путь SSH |
| 9 | k3d заменяет модель ручной VM — тот же образ мышления IaC, другая единица |
| 13 | ArgoCD берёт на себя развёртывания; ваш IaC по-прежнему определяет кластер |

> **Помните:** если вы не можете выполнить `git clone && terraform apply` с нуля, это не IaC — это история кликов в консоли. Никаких секретов в коде, никакого state в Git. Пять правил со слайда 22 лекции 4 оплачены реальными деньгами (слайд 23).
