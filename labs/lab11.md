# Лабораторная работа 11 — Секреты Kubernetes & OpenBao

![difficulty](https://img.shields.io/badge/difficulty-intermediate-yellow)
![topic](https://img.shields.io/badge/topic-Secret%20Management-blue)
![points](https://img.shields.io/badge/points-10%2B2-orange)
![tech](https://img.shields.io/badge/tech-OpenBao%202.5%20%7C%20K8s%20Secrets-informational)

> **Цель:** перестаньте класть пароли в Git. Убедите себя, что Kubernetes `Secret` — это **не** шифрование, затем централизуйте секреты в **OpenBao 2.5.0** с политикой только для чтения, обеспечивающей наименьшие привилегии.
> **Результат сдачи:** PR из ветки `lab11`, добавляющий `k8s/secrets/` (политика + пример Secret), `k8s/lab10-app/templates/secret.yaml` в ваш чарт из лабораторной 10 и `docs/LAB11.md` с **реальными** доказательствами (ваши декодированные значения, ваш `bao kv get`, ваш отклонённый write).

---

## Обзор

В этой лабораторной работе вы отработаете:
- Создание `kind: Secret` и **самостоятельное декодирование его base64**, чтобы вдолбить: base64 ≠ шифрование
- Поднятие **OpenBao 2.5.0** в dev-режиме и изучение контракта переменных окружения (`BAO_ADDR`, `BAO_TOKEN`), который будет переиспользоваться в любой последующей производственной настройке
- Написание **политики HCL только для чтения** и токена, привязанного к ней, затем доказательство политики попыткой — и неудачей — записи
- Шаблонизирование `Secret` в ваш чарт из лабораторной 10 **без** коммита реального значения (значение приходит из `--set`/`-f` во время установки)
- Выбор одного из двух производственных паттернов инъекции: **OpenBao Agent Injector** ИЛИ **External Secrets Operator (ESO)**

> ⚠️ **Область:** только OpenBao в dev-режиме (in-memory, один ключ, авто-распечатывание). Производственный OpenBao (хранилище Raft, авто-unseal через облачный KMS, audit device, TLS) вне области — но политики и роли, которые вы здесь пишете, той же формы.

> 💡 **Пять инцидентов, с которых началась лекция — Code Spaces 2014, Uber 2016, Toyota 2022, Dropbox 2022, tj-actions 2025 — каждый до единого был учётными данными, хранящимися не в том месте.** Не zero-day. Не изощрённый 0-click. Просто секрет в коде, каталог `.git/`, отдаваемый веб-сервером, фишинг GitHub-аккаунта, скомпрометированный GitHub Action, вываливающий `env` в логи. Эта лабораторная учит скучным вещам, которые предотвратили бы все пять.

---

## Состояние проекта

**У вас должно быть из предыдущих лабораторных:**
- Лабораторная 9: кластер k3d 1.36 (`k3d cluster create devops`) с работающими сервисами `web` + `echo`
- Лабораторная 10: чарт Helm в `k8s/lab10-app/` с `Chart.yaml`, `values.yaml`, `templates/`, `_helpers.tpl`

**Эта лабораторная добавляет:**
- `k8s/secrets/app-credentials.yaml` — ваш написанный вручную манифест `Secret` (демо base64)
- `k8s/lab10-app/templates/secret.yaml` — шаблонизированный `Secret` в вашем чарте
- `k8s/secrets/lab11-read.hcl` — политика OpenBao только для чтения
- `docs/LAB11.md` — ваш отчёт о сдаче с зафиксированными доказательствами из CLI
- *(бонус)* либо `k8s/secrets/injector.yaml` (аннотации Agent Injector), либо `k8s/secrets/eso.yaml` (CRD SecretStore + ExternalSecret)

---

## Настройка

Вам нужно (проверьте перед началом):

- `kubectl version --client` → 1.36.x (из лабораторной 9)
- `helm version` → 4.1.x (из лабораторной 10)
- `k3d cluster list` показывает кластер `devops` из лабораторной 9 в состоянии Running
- **OpenBao 2.5.0** установлен локально. Установите через brew tap (`brew install openbao/tap/bao`) или скачав tarball Linux-бинарника `v2.5.0` с `github.com/openbao/openbao/releases` и распаковав его в `PATH`.
- `bao version` должен напечатать `OpenBao v2.5.0`

Создайте пространство имён + ServiceAccount, которые переиспользуют дальнейшие задачи:

```bash
kubectl create namespace lab11
kubectl create serviceaccount lab11-sa -n lab11
```

> **`bao` — это drop-in замена `vault`.** OpenBao сохранил сетевой протокол, подкоманды CLI и эндпоинты API. Если у вас есть старая мышечная память на `vault kv put ...`, она по-прежнему работает против сервера OpenBao. Мы используем `bao` в этой лабораторной, потому что установленный вами бинарник — это OpenBao, а не HashiCorp Vault.

> 📜 **Выноска про BSL в одном абзаце.** В августе 2023 HashiCorp перелицензировал Vault под Business Source License 1.1 — source-available, но с запретом на конкуренцию, который воспрещает коммерческие managed-service предложения, конкурирующие с HashiCorp. Linux Foundation форкнула Vault 1.14 как **OpenBao** под MPL-2.0 (настоящий open source). OpenBao 2.0 вышел в GA в марте 2024; 2.5.0 (4 февраля 2026) добавил бесплатные Namespaces и горизонтальную масштабируемость чтения — возможности, которые раньше были платным барьером HashiCorp Enterprise. Всё, что вы пишете в этой лабораторной, переносимо на любой из серверов; мы стандартизируем на OpenBao, чтобы манифесты пережили любую будущую перелицензировку.

---

## Задача 1 — Секреты Kubernetes и ловушка base64 (2 балла)

### 1.1 — Напишите вручную манифест `kind: Secret`

`ВАША ЗАДАЧА`: создайте `k8s/secrets/app-credentials.yaml`, содержащий `kind: Secret` для вымышленной базы данных с именем пользователя `app` и паролем на ваш выбор. Используйте **декларативную** форму (YAML-файл, который вы `kubectl apply`), а не `kubectl create secret`.

Вы решаете:
- Значение `type:` — выберите из `Opaque`, `kubernetes.io/dockerconfigjson` или `kubernetes.io/tls`. Неверный выбор не проходит валидацию, так что выбор важен. В `docs/LAB11.md` обоснуйте, почему ваш выбор подходит для обычных username+password.
- Два ключа `data:` — назовите их так, как их потребляло бы реальное приложение (в стиле переменных окружения).
- Значения, закодированные в base64 — вычислите их сами с помощью `base64`; **не** используйте сокращение `stringData:` в этой задаче. Смысл — прочувствовать шаг кодирования вручную.

Скелет (заполните маркеры YOUR-TASK):

```yaml
# k8s/secrets/app-credentials.yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-credentials
  namespace: lab11
type: YOUR-TASK                 # which built-in type fits username+password?
data:
  YOUR-TASK: YOUR-TASK          # echo -n 'app' | base64
  YOUR-TASK: YOUR-TASK          # echo -n '<your password>' | base64
```

> ⚠️ **`echo` vs `echo -n`** — `echo "foo" | base64` включает завершающий перевод строки (`Zm9vCg==`); `echo -n "foo" | base64` — нет (`Zm9v`). Перевод строки молча ломает сравнения паролей в потребляющем приложении и является самой частой ошибкой base64 в прогонах. Используйте `-n`.

Примените его, затем прочитайте обратно:

```bash
kubectl apply -f k8s/secrets/app-credentials.yaml
kubectl get secret app-credentials -n lab11 -o yaml
```

### 1.2 — Декодируйте сами и докажите суть

`ВАША ЗАДАЧА`: выполните однострочник, который достаёт **ваш собственный** Secret из кластера и пропускает поле пароля через `base64 -d`, восстанавливая открытый текст. Зафиксируйте вывод дословно в `docs/LAB11.md` под заголовком **"Момент озарения с base64"**.

Подсказка (форма команды — впишите имя ключа, которое вы выбрали):

```bash
kubectl get secret app-credentials -n lab11 \
  -o jsonpath='{.data.YOUR-TASK}' | base64 -d ; echo
```

В **2–3 предложениях** в вашем `docs/LAB11.md` ответьте: *зачем API K8s вообще использует здесь base64, если это не для безопасности?* (Подсказка: значения `Secret.data` должны быть валидными строками JSON/YAML; бинарные данные вроде TLS-ключа не пережили бы транспортировку.)

### 1.3 — Шифрование etcd в состоянии покоя, своими словами

Напишите абзац в `docs/LAB11.md`, отвечающий на все три:
- Шифруются ли секреты Kubernetes в состоянии покоя по умолчанию? (Подсказка: поищите `EncryptionConfiguration`.)
- Что делает провайдер KMS в этой конфигурации такого, чего не делает провайдер `aescbc`?
- Почему включение `EncryptionConfiguration` необходимо, но **недостаточно** для продакшена — от чего оно вас не защищает? (Подсказка: любой с RBAC `system:masters`.)

### 1.4 — Подтверждение работы

Вставьте в `docs/LAB11.md`:

- Содержимое `k8s/secrets/app-credentials.yaml` (ваш реальный файл, ваши реальные строки base64)
- Вывод `kubectl get secret app-credentials -n lab11 -o yaml | grep -A2 ^data:`
- Однострочник декодирования base64 **и его вывод в открытом виде**, показывающий, что вы восстановили свой пароль
- Ваш ответ в 2–3 предложения на *зачем base64?* и абзац про etcd-в-покое из 1.3

---

## Задача 2 — Секреты, управляемые Helm (3 балла)

### 2.1 — Шаблонизированный Secret в чарте из лабораторной 10

`ВАША ЗАДАЧА`: добавьте `templates/secret.yaml` в ваш чарт из лабораторной 10 (`k8s/lab10-app/templates/secret.yaml`). Он должен рендерить `kind: Secret`, названный по хелперу `fullname` чарта, нести стандартные labels чарта и потреблять **два** значения из `.Values.secret` — `dbUsername` и `dbPassword`.

Критические правила:
- Используйте `stringData:` (чтобы Helm не кодировал дважды); API K8s сам кодирует в base64 на своей стороне.
- В `values.yaml` установите оба поля в **строки-заглушки** (`"PLACEHOLDER_USER"`, `"PLACEHOLDER_PASS"`). Реальные значения приходят из `--set` или `-f override.yaml` во время установки — *никогда* не коммитятся.

Скелет (заполните маркеры YOUR-TASK):

```yaml
# k8s/lab10-app/templates/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: YOUR-TASK              # use the fullname helper from your _helpers.tpl
  labels:
    YOUR-TASK                  # use the labels helper from your _helpers.tpl
type: YOUR-TASK                # same choice as Task 1.1
stringData:
  DB_USERNAME: YOUR-TASK       # quote a value pulled from .Values.secret.*
  DB_PASSWORD: YOUR-TASK
```

И в `values.yaml`:

```yaml
secret:
  dbUsername: "PLACEHOLDER_USER"
  dbPassword: "PLACEHOLDER_PASS"   # override at install time, NEVER commit real values
```

### 2.2 — Потребляйте его в Deployment

`ВАША ЗАДАЧА`: отредактируйте существующий шаблон Deployment вашего чарта (`templates/deployment.yaml`), чтобы контейнер `web` читал оба ключа как переменные окружения. Используйте паттерн `envFrom` + `secretRef` (чище, чем `secretKeyRef` на каждый ключ, когда весь Secret предназначен одному потребителю).

Скелет (заполните маркер YOUR-TASK):

```yaml
containers:
  - name: web
    image: # ... your Lab 10 image ...
    envFrom:
      - secretRef:
          name: YOUR-TASK      # same helper-rendered name as in Task 2.1
```

### 2.3 — Установите с реальным значением вне полосы

`ВАША ЗАДАЧА`: установите (или обновите) чарт, передав реальный пароль через `--set` **или** через `-f local-secrets.yaml`, который находится в `.gitignore`. Затем проверьте в работающем pod'е.

> ⚠️ **Ловушка `--set` в логах CI.** `helm upgrade --install ... --set secret.dbPassword='hunter2'` нормально на вашем ноутбуке. В CI это окажется в логе workflow, если переменная не обёрнута как secret (`${{ secrets.DB_PASSWORD }}` в GHA) **и** вы не сделаете `helm upgrade ... --set secret.dbPassword="$DB_PASSWORD"` без echo. Задокументируйте в `docs/LAB11.md`, какой паттерн вы использовали бы в настоящем GitHub Action.

> 🔮 **Предпросмотр лабораторной 13 — `--set` НЕ переживает ArgoCD.** На следующей неделе ArgoCD будет синхронизировать этот же чарт из Git, и он учитывает только `helm.valueFiles` / `helm.valuesObject` в CR `Application` — **нет ручки `--set`** при GitOps-согласовании. Поэтому бонусная задача устанавливает **OpenBao Agent Injector** или **ESO**: они доставляют секрет вне полосы, чтобы чарт в Git мог поставляться с заглушками навсегда. Если пропустите бонус, обходной путь для лабораторной 13 — `helm.valuesObject`, ссылающийся на Secret, управляемый извне — никогда не реальное значение в Git.

Команды проверки (иллюстративные — ваш вывод будет отличаться):

```bash
helm upgrade --install lab10-app k8s/lab10-app -n lab11 \
  --set secret.dbPassword='YOUR-PASSWORD'         # YOUR-TASK: pick a value

# Find the actual web Deployment name — your fullname helper decides it; don't
# guess it. The `app.kubernetes.io/name=lab10-app` label matches both web and echo
# (they share the chart), so filter on the `-web` suffix in the name to get only web:
WEB=$(kubectl get deploy -n lab11 -l app.kubernetes.io/name=lab10-app \
       -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -- '-web$' | head -1)
kubectl exec -n lab11 deploy/"$WEB" -- env | grep '^DB_'
# DB_USERNAME=app
# DB_PASSWORD=YOUR-PASSWORD                       # ← present in pod env
kubectl describe pod -n lab11 -l app.kubernetes.io/name=lab10-app | grep -A1 -i secret
# (the Secret name appears; the value does NOT — describe redacts envFrom values)
```

### 2.4 — Подтверждение работы

Вставьте в `docs/LAB11.md`:

- Ваш `templates/secret.yaml` и соответствующий фрагмент `values.yaml` (только значения-заглушки — *никакого реального пароля*)
- Команду `helm upgrade ... --set`, которую вы реально выполняли (можете отредактировать пароль на `***`)
- Вывод `kubectl exec ... env | grep ^DB_`, доказывающий, что значения попали в контейнер (здесь тоже можете отредактировать пароль на `***`)
- Ответ в 2–3 предложения «как я сделал бы это в CI»

---

## Задача 3 — Интеграция с OpenBao (3 балла)

Это главная задача. Вы поднимете OpenBao, изучите **контракт переменных окружения**, который переиспользует любая последующая производственная настройка, напишете **политику HCL только для чтения** и докажете политику, попытавшись записать — и потерпев неудачу.

### 3.1 — Поднимите dev-сервер

`ВАША ЗАДАЧА`: запустите dev-сервер OpenBao с **запоминающимся** ID корневого токена (вы будете использовать его для входа). Затем экспортируйте две переменные окружения, от которых зависит каждая команда `bao`.

Скелет (заполните маркеры YOUR-TASK — и да, **смысл** этих пропусков в том, чтобы вы проинтернализировали контракт):

```bash
# Start the dev server in the background. -dev = unsealed + in-memory.
# Redirect output to a log file so server lines don't tangle with your prompt.
bao server -dev -dev-root-token-id=___ >/tmp/bao.log 2>&1 &   # YOUR-TASK: pick a token id (e.g. 'devroot')

# Two env vars EVERY bao command needs:
export BAO_ADDR=___                              # YOUR-TASK: the dev server URL (default port is 8200)
export BAO_TOKEN=___                             # YOUR-TASK: must match the -dev-root-token-id above

# Give the listener ~1s to come up before the first call, or poll bao status.
sleep 1
bao status                                       # Sealed false, Storage Type inmem, Version 2.5.0
```

> 🧹 **Остановка dev-сервера.** Это самая недавняя фоновая задача в вашей оболочке — `kill %1` (или `kill $(pgrep -f 'bao server -dev')`), когда закончите. Перезапуск стирает каждый секрет (INMEM); в этом весь смысл.

> 💡 **Контракт:** каждый клиент `bao` (или `vault`) — ваш CLI, ваши приложения, провайдер ESO, инжектор Agent — аутентифицируется по `BAO_ADDR` + токену. В dev-режиме токен — это корневой токен. В продакшене токен приходит из **метода аутентификации** (JWT Kubernetes ServiceAccount, AppRole, OIDC), он короткоживущий и ограничен политикой. Имена переменных окружения те же.

> ⚠️ **Dev-сервер — INMEM.** Каждый положенный вами секрет исчезает при перезапуске процесса. Это намеренно — это делает лабораторную быстрой, а модель безопасности безошибочно понятной.

### 3.2 — Положите и получите секрет на пути KV-v2

`ВАША ЗАДАЧА`: включите движок секретов KV-v2 на пути на ваш выбор, затем запишите секрет, содержащий **как минимум две** пары ключ-значение, на пути на ваш выбор, затем прочитайте одно из полей обратно.

Скелет:

```bash
# YOUR TASK lines below:
#   -path=:  pick the mount path (convention: 'secret')
#   put arg: the mount path you chose + a logical name (e.g. secret/lab11/db)
#   first  field=value: a username (use a literal — never a real password)
#   second field=value: a password (literal, not from env)
#   get:     read back one field by name

bao secrets enable -path=___ kv-v2

bao kv put ___/lab11/db \
  ___=app \
  ___=hunter2

bao kv get -field=___ ___/lab11/db
```

> ⚠️ **Подвох пути KV-v1 vs KV-v2.** `bao kv put secret/foo k=v` пишет *логический* путь `secret/foo`, но **API**-путь в KV-v2 — это `secret/data/foo` (со вставленным сегментом `data/`). Политики и инжектор Agent ссылаются на API-путь — так что правило HCL должно гласить `path "secret/data/lab11/db"`, а не `path "secret/lab11/db"`. Забыть это — способ №1, которым «корректная» политика отклоняет чтение.

> ⚠️ **`bao kv put` vs `bao write` на одном и том же data-пути.** KV-v2 версионирует данные под `data/`; `bao write secret/data/foo data='{"k":"v"}'` работает, но использует другую JSON-форму, чем `bao kv put`. Придерживайтесь `bao kv put` / `bao kv get` для KV-v2; `bao write` — для всего остального (auth backends, политики, роли).

### 3.3 — Напишите политику только для чтения

`ВАША ЗАДАЧА`: создайте `k8s/secrets/lab11-read.hcl` с одной секцией, которая даёт **read** на точный data-путь вашего секрета и **ничего больше**. Ни `list`, ни `update`, ни `delete`, ни glob — весь смысл в наименьших привилегиях.

Скелет (заполните маркеры YOUR-TASK):

```hcl
# k8s/secrets/lab11-read.hcl
path "___" {                                     # YOUR-TASK: the API path to the secret you wrote in 3.2
  capabilities = [___]                           # YOUR-TASK: a single-element list, the minimum verb
}
```

Примените её и создайте привязанный к ней токен:

```bash
bao policy write lab11-read k8s/secrets/lab11-read.hcl
APP_TOKEN=$(bao token create -policy=lab11-read -ttl=1h -field=token)
echo "$APP_TOKEN"      # save for the next step
```

### 3.4 — Докажите политику, попытавшись её нарушить

`ВАША ЗАДАЧА`: войдите под новым токеном (установите `BAO_TOKEN=$APP_TOKEN`), затем выполните **две** команды и зафиксируйте оба вывода:

1. `bao kv get -field=...`, который **успешен** (политика разрешает чтение).
2. `bao kv put ...` на тот же путь, который **падает** с 403 (политика не разрешает запись).

Неудача второй команды — это доказательство. Если она успешна, ваша политика дала слишком много — вернитесь к 3.3.

Скелет:

```bash
BAO_TOKEN=$APP_TOKEN bao kv get -field=___ ___/lab11/db    # YOUR-TASK: should print the value
BAO_TOKEN=$APP_TOKEN bao kv put ___/lab11/db ___=evil      # YOUR-TASK: should fail with 403
# Error writing data to secret/data/lab11/db: ...permission denied
```

Восстановите свой корневой токен для любой очистки: `export BAO_TOKEN=<your-dev-root-token-id>`.

### 3.5 — Подтверждение работы

Вставьте в `docs/LAB11.md`:

- `bao version` (должен показать 2.5.0)
- Точную строку `bao server -dev -dev-root-token-id=...` и строки `export BAO_ADDR`/`BAO_TOKEN` (контракт переменных окружения — можете отредактировать токен)
- `bao status`, показывающий `Sealed false`, `Storage Type inmem`, `Version 2.5.0`
- Подтверждение создания `bao kv put ...` + `bao kv get -field=...`, возвращающий ваше значение
- Содержимое `k8s/secrets/lab11-read.hcl` (ваша реальная политика)
- **Два** вывода из 3.4 рядом — успешное чтение и запись, падающая с `permission denied`. **Это главное доказательство.**

---

## Задача 4 — Документация (2 балла)

`ВАША ЗАДАЧА`: завершите `docs/LAB11.md` этими разделами по порядку:

1. **Момент озарения с base64** — ваш декодированный открытый текст (1.2) + абзац «зачем тогда base64?» (1.3)
2. **Шифрование etcd в состоянии покоя** — абзац из 1.3, охватывающий KMS vs `aescbc` и от чего `EncryptionConfiguration` не защищает
3. **Секрет, управляемый Helm** — фрагмент чарта, команда установки (отредактированная), доказательство env в pod'е (2.4)
4. **Рабочий процесс OpenBao** — контракт переменных окружения, KV-v2 put/get, политика только для чтения + доказательство отклонённой записи (3.5)
5. **История Vault → OpenBao** — один абзац: BSL август 2023, форк LF, почему OpenBao для этого курса
6. **Анализ безопасности** — когда нативного K8s Secret достаточно, а когда нужен OpenBao; что dev-режим скрывает от вас, а продакшен обнажает (нет Raft, нет audit device, нет авто-unseal, нет TLS); 2–3 предложения об альтернативах SOPS / Sealed Secrets и когда они имеют смысл
7. **Производственный чек-лист** — пять пунктов, которые вы реально вписали бы в документ по харденингу прода (роли с наименьшими привилегиями, audit device и т.д.)

---

## Бонусная задача — выберите ОДНУ (2 балла)

Выберите **A** или **B**. Обе по 2 балла. **Не делайте обе.** Здесь намеренно меньше подсказок — вы это заслужили.

### Вариант A — OpenBao Agent Injector

Вы устанавливаете Agent Injector через чарт Helm OpenBao, аннотируете pod и доказываете, что секрет попадает на диск внутри pod'а без ведома приложения об OpenBao.

**Обязательные артефакты** (в `k8s/secrets/injector.yaml`):

1. **Аннотации** в шаблоне pod'а, которые запускают инъекцию. Имена ниже — это контракт — заполните значения; имена, оканчивающиеся на `-<file>`, шаблонизируются *вами* (часть с именем файла становится именем файла под `/vault/secrets/`):

   ```yaml
   # k8s/secrets/injector.yaml — annotations: section of your pod template
   vault.hashicorp.com/agent-inject: "true"
   vault.hashicorp.com/role: YOUR-TASK                          # the OpenBao role you create below
   vault.hashicorp.com/agent-inject-secret-YOUR-TASK: YOUR-TASK # filename : the KV API path (mind the data/ segment)
   vault.hashicorp.com/agent-inject-template-YOUR-TASK: |       # render the secret as a .env-style file (>=2 keys)
     YOUR-TASK
   ```

2. `serviceAccountName: lab11-sa` в спеке pod'а — ServiceAccount, чей JWT валидирует OpenBao.

**Обязательная конфигурация OpenBao** (выполните внутри pod'а сервера openbao):

- `bao auth enable kubernetes` и `bao write auth/kubernetes/config kubernetes_host=...`
- `bao write auth/kubernetes/role/lab11 ...`, который привязывает `lab11-sa`, пространство имён `lab11`, политику `lab11-read` и разумный `ttl`.

**Подтверждение работы:**

- `kubectl get pods -n openbao`, показывающий pod инжектора Running
- `kubectl describe pod -n lab11 <your-pod>`, показывающий **инжектированный init-контейнер + sidecar** (`vault-agent-init` и `vault-agent`), которых вы НЕ добавляли
- `kubectl exec -n lab11 <your-pod> -c <app-container> -- cat /vault/secrets/db`, показывающий отрендеренный файл (можете отредактировать значение — важно *существование* файла)

> Инжектор — это **MutatingAdmissionWebhook**. Он правит ваш podspec во время admission. Поэтому в вашем YAML *один* контейнер, а в работающем pod'е *три* — webhook добавил два. Это тот же механизм, который Istio использует для своего sidecar envoy.

### Вариант B — External Secrets Operator (ESO)

Вы устанавливаете ESO через Helm, направляете `SecretStore` на ваш сервер OpenBao, и `ExternalSecret` создаёт **нативный K8s Secret**, который ваше приложение потребляет через `envFrom: secretRef`. Приложение никогда не знает, что ESO существует.

**Обязательные артефакты** (в `k8s/secrets/eso.yaml`):

1. CRD `SecretStore` (`apiVersion: external-secrets.io/v1`) с именем `openbao` в пространстве имён `lab11`, с блоком `provider.vault` (провайдер `vault` в ESO совместим с OpenBao). Он использует auth `kubernetes`, роль, которую вы создаёте в OpenBao, и `serviceAccountRef: {name: lab11-sa}`.
2. CRD `ExternalSecret`, создающий нативный Secret `db-creds`.

Скелет (заполните маркеры YOUR-TASK — имена полей CRD — это контракт):

```yaml
# k8s/secrets/eso.yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata: {name: openbao, namespace: lab11}
spec:
  provider:
    vault:
      server: YOUR-TASK                 # the in-cluster URL of the OpenBao server (Service DNS + port)
      path: YOUR-TASK                   # the KV mount path you chose in Task 3.2
      version: YOUR-TASK                # KV engine version
      auth:
        kubernetes:
          mountPath: kubernetes
          role: YOUR-TASK               # the OpenBao role bound to lab11-sa
          serviceAccountRef: {name: lab11-sa}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: db, namespace: lab11}
spec:
  refreshInterval: YOUR-TASK            # production default vs demo: pick deliberately
  secretStoreRef: {name: openbao, kind: SecretStore}
  target: {name: YOUR-TASK}             # the native K8s Secret ESO will produce (consumed by your app)
  data:
    - secretKey: YOUR-TASK              # the key as it appears IN the produced K8s Secret
      remoteRef: {key: YOUR-TASK, property: YOUR-TASK}  # the OpenBao logical path + the field name in it
    # YOUR-TASK: add a second key — username — with the same shape
```

**Обязательная конфигурация OpenBao:** та же Kubernetes auth + привязка роли, что и в варианте A (это тот же метод аутентификации).

**Обязательная обвязка приложения:** отредактируйте ваш чарт из лабораторной 10, чтобы потреблять `db-creds` через `envFrom: secretRef`. Обратите внимание, что приложение теперь читает *нативный K8s Secret* — никакого sidecar, никаких аннотаций, никакого клиента OpenBao в pod'е. ESO выполняет синхронизацию вне полосы.

**Подтверждение работы:**

- `kubectl get pods -n external-secrets`, показывающий контроллер ESO Running
- `kubectl get externalsecret db -n lab11`, показывающий `STATUS: SecretSynced`
- `kubectl get secret db-creds -n lab11`, показывающий, что созданный ESO Secret существует
- `kubectl exec -n lab11 deploy/lab10-app-web -- env | grep ^DB_`, показывающий, что значения попали в приложение

> ESO **опрашивает** OpenBao каждый `refreshInterval`. Для демо уменьшите его (например, `30s`), но `1h` — производственное умолчание — ротация в OpenBao не распространяется мгновенно. Этот компромисс — главное отличие от Agent Injector (который обновляется по lease токена).

**Бонусная документация:** добавьте в `docs/LAB11.md` раздел с использованным манифестом, скриншотами-доказательствами выше и **одним абзацем** о том, почему вы выбрали A или B для того типа приложения, с которым хотели бы это запускать (подумайте: «динамические учётные данные БД с TTL 15 минут» → Agent Injector; «каждый микросервис в монорепе на 50 pod'ов читает одну и ту же горстку секретов» → ESO).

---

## Как сдавать

```bash
git switch -c lab11
git add k8s/secrets/ k8s/lab10-app/templates/secret.yaml \
        k8s/lab10-app/values.yaml docs/LAB11.md
# also stage k8s/secrets/injector.yaml (Option A) OR k8s/secrets/eso.yaml (Option B) if you did the bonus
git commit -m "feat(lab11): secrets + OpenBao (read-only policy, base64 demo)"
git push -u origin lab11
```

Откройте **два** PR:

- `your-fork:lab11` → `course-repo:master` *(на проверку)*
- `your-fork:lab11` → `your-fork:master`

Чек-лист PR:

```text
- [ ] Task 1 — app-credentials.yaml + base64 decode proof in docs/LAB11.md
- [ ] Task 2 — templates/secret.yaml in chart, placeholders only in values.yaml, env proof
- [ ] Task 3 — bao 2.5.0 dev server, BAO_ADDR/BAO_TOKEN exported, KV put/get, read-only policy, denied-write proof
- [ ] Task 4 — docs/LAB11.md has all 7 sections
- [ ] Bonus (optional) — Agent Injector OR ESO with proof captures
- [ ] No real secret values in any committed file (grep your diff before pushing)
```

---

## Критерии приёмки

### Задача 1 (2 балла)
- ✅ `k8s/secrets/app-credentials.yaml` — ваш собственный написанный вручную `kind: Secret` с осознанным выбором `type:` и двумя ключами `data:` в base64
- ✅ `docs/LAB11.md` содержит однострочник декодирования base64 **с вашим собственным выводом в открытом виде**
- ✅ Ответ «Зачем base64?» и абзац про etcd-в-покое присутствуют и корректны

### Задача 2 (3 балла)
- ✅ `k8s/lab10-app/templates/secret.yaml` существует, использует хелперы имени + labels чарта и читает из `.Values.secret.*`
- ✅ `values.yaml` поставляет **только строки-заглушки** — никакого реального пароля
- ✅ Deployment потребляет Secret через `envFrom: secretRef`
- ✅ Env в pod'е подтверждён через `kubectl exec ... env | grep ^DB_`; `kubectl describe` НЕ показывает значения
- ✅ `docs/LAB11.md` документирует CI-паттерн, который вы использовали бы, чтобы избежать утечки пароля через `--set`

### Задача 3 (3 балла)
- ✅ `bao version` показывает 2.5.0
- ✅ Был запущен `bao server -dev -dev-root-token-id=...`; экспортированы `BAO_ADDR` и `BAO_TOKEN`
- ✅ KV-v2 включён, секрет записан с ≥ 2 ключами, прочитан обратно через `bao kv get -field=...`
- ✅ `k8s/secrets/lab11-read.hcl` даёт **только read** на точный data-путь (без glob, без лишних capabilities)
- ✅ Доказательство отклонённой записи (`bao kv put ...` → `permission denied`) зафиксировано в `docs/LAB11.md`

### Задача 4 (2 балла)
- ✅ `docs/LAB11.md` имеет все семь разделов (1.2 + 1.3, etcd-в-покое, Helm, OpenBao, история Vault→OpenBao, анализ безопасности, производственный чек-лист)

### Бонус (2 балла) — только один вариант
- ✅ **A:** Agent Injector развёрнут; инжектированные init+sidecar видны в `kubectl describe pod`; `/vault/secrets/<file>` существует в контейнере приложения; кастомный шаблон рендерит многоключевой `.env`
- ✅ **B:** ESO установлен; `ExternalSecret` показывает `SecretSynced`; нативный Secret `db-creds` существует; env в pod'е приложения содержит значения

---

## Рубрика

| Задача | Баллы | Критерии |
|------|-------:|----------|
| **Задача 1** — Секреты K8s и ловушка base64 | **2** | Написанный вручную Secret, декодированный открытый текст, объяснение base64 vs шифрование, понимание etcd-в-покое |
| **Задача 2** — Секрет, управляемый Helm | **3** | Шаблонизированный Secret, значения-заглушки, обвязка envFrom, реальное значение инжектируется при установке, CI-паттерн задокументирован |
| **Задача 3** — Интеграция с OpenBao | **3** | Dev-сервер поднят, контракт переменных окружения проинтернализирован, KV-v2 put/get, политика только для чтения работает (доказательство отклонённой записи) |
| **Задача 4** — Документация | **2** | Все семь разделов присутствуют, анализ безопасности настоящий, история BSL/OpenBao корректна |
| **Бонус** — Injector ИЛИ ESO | **2** | Работающая инъекция (A) или синхронизация (B) с манифестами + доказательствами |
| **Итого** | **12** | 10 основных + 2 бонусных |

**Диапазоны оценивания:**
- **10/10:** Все четыре основные задачи выполнены, доказательство отклонённой записи реально, реальные секреты не закоммичены, анализ безопасности показывает настоящее понимание
- **8–9/10:** Все задачи выполнены с небольшими пробелами в документации или одним недостающим скриншотом-доказательством
- **6–7/10:** Задачи 1+2 основательны, OpenBao поднят, но политика слишком разрешительная (нет доказательства отклонённой записи) или неверен путь KV
- **<6/10:** OpenBao не работает, демо base64 отсутствует, или закоммичены реальные секреты

---

## Ресурсы

<details>
<summary>📚 Документация</summary>

- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) — concepts + the `type:` table
- [Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) — EncryptionConfiguration, KMS provider, key rotation
- [OpenBao docs](https://openbao.org/docs/) — `bao` CLI, KV-v2, auth methods, policies
- [OpenBao 2.5.0 release notes](https://openbao.org/community/release-notes/2-5-0/) — Feb 4 2026
- [OpenBao Kubernetes auth](https://openbao.org/docs/auth/kubernetes/) — TokenReview API, role binding
- [Vault Agent annotations (OpenBao-compatible)](https://developer.hashicorp.com/vault/docs/platform/k8s/injector/annotations) — annotation reference
- [External Secrets Operator](https://external-secrets.io/) — CRDs + provider list
- [ESO Vault/OpenBao provider](https://external-secrets.io/latest/provider/hashicorp-vault/) — config shape

</details>

<details>
<summary>⚠️ Частые ловушки (из реальных прогонов)</summary>

- **Base64 — это кодирование, а не шифрование.** `kubectl get secret -o yaml | grep -A1 data:` с последующим `| base64 -d` восстанавливает открытый текст **без ключа** — факт №1, в котором ошибается каждый джун. Если вы унесёте из этой лабораторной одну вещь, унесите эту.
- **`echo` добавляет завершающий перевод строки.** `echo "foo" | base64` ≠ `echo -n "foo" | base64`. Перевод строки молча делает пароли недействительными внутри приложения. Используйте `-n`.
- **Шифрование etcd в состоянии покоя требует KMS, а не только `aescbc`.** Провайдеры `aescbc` с локальным ключом хранят ключ на том же диске, что и данные, которые они «защищают» — ключ лежит рядом с замком. Провайдеры KMS (AWS KMS, GCP KMS, OpenBao Transit) держат ключ вне кластера.
- **Dev-сервер OpenBao — INMEM.** Перезапустите процесс, и каждый секрет исчезнет. В этом смысл — dev-режим для изучения API, а не для хранения чего-либо. Перечитайте слайд лекции про анти-паттерн запуска dev-режима в проде.
- **Разница путей KV-v1 vs KV-v2.** `bao kv put secret/foo k=v` пишет *логический* путь; политики и инжектор Agent должны ссылаться на **API**-путь (`secret/data/foo`, с вставленным `data/`), иначе чтение молча отклоняется. Тот же подвох живёт в поле `remoteRef.key` в ESO.
- **`bao kv put` vs `bao write`.** Оба трогают один и тот же путь в KV-v2, но используют разные JSON-формы; придерживайтесь `kv put`/`kv get` для KV-v2, чтобы избежать несоответствия формы.
- **Helm `--set` утекает в логи CI.** `helm upgrade ... --set db.password='hunter2'` в логе GitHub Action — это готовый Code Spaces / tj-actions. Оборачивайте как `${{ secrets.* }}` и ссылайтесь через переменную окружения; лучше используйте настоящий менеджер секретов и позвольте ESO/Agent Injector доставить значение.
- **`automountServiceAccountToken: true` по умолчанию.** Каждый pod получает токен SA, нужен он ему или нет. Для pod'ов, которые не общаются с API K8s или OpenBao, установите `false`, чтобы уменьшить радиус поражения.
- **`vault.hashicorp.com/role: admin` — это новый `--privileged`.** Привязывайте по одной роли на приложение на окружение. Наименьшие привилегии — весь смысл политики, которую вы написали в 3.3.
- **Корневой токен dev-режима в истории вашей оболочки.** `export BAO_TOKEN=root` переживает в `~/.bash_history`. Используйте уникальное значение на каждую dev-сессию и очищайте его (`unset BAO_TOKEN`), когда закончите.

</details>

<details>
<summary>🛠️ Инструменты, которые стоит знать</summary>

- [gitleaks](https://github.com/gitleaks/gitleaks) — pre-commit + CI scanner; catches the human moments
- [trufflehog](https://github.com/trufflesecurity/trufflehog) — deeper detector, finds high-entropy strings in git history
- [SOPS](https://getsops.io/) — file-level encryption with KMS/age/PGP; GitOps-friendly
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) — per-cluster public-key encryption; CRD + controller
- [k9s](https://k9scli.io/) — terminal UI; `:secret` shows them all at once

</details>

---

## Взгляд вперёд

| Лабораторная | Что добавляет |
|---:|---|
| 12 | ConfigMaps + PVC — неконфиденциальная конфигурация + постоянное состояние переживает удаление pod'а |
| 13 | ArgoCD GitOps — ваш защищённый чарт развёртывается через Application/ApplicationSet |
| 14 | Canary Argo Rollouts; секреты ротируются под прогрессивной доставкой |
| 15 | StatefulSets — стабильная идентичность + PVC на pod + секреты на реплику |
| 16 | Стек kube-prometheus — сбор `/sys/metrics` у OpenBao |

**Удачи.** 🔐

> **Помните:** момент, когда вы декодировали свой собственный Secret через `base64 -d` и получили обратно открытый текст — это момент, когда вы поняли, почему каждую утечку из списка инцидентов лекции можно было предотвратить. Сохраните это чувство. Несите его в каждый ревью PR, где кто-то «просто пока» кладёт реальное значение в `values.yaml`.
