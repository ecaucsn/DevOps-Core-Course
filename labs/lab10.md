# Лабораторная работа 10 — Пакетный менеджер Helm

![difficulty](https://img.shields.io/badge/difficulty-intermediate-yellow)
![topic](https://img.shields.io/badge/topic-Helm-blue)
![points](https://img.shields.io/badge/points-10%2B2-orange)
![tech](https://img.shields.io/badge/tech-Helm%204-informational)

> **Цель:** преобразовать ваши манифесты Kubernetes из лабораторной 9 в написанный вручную чарт Helm 4, который проходит через dev / staging / prod с одним файлом values на окружение, запускает хук жизненного цикла и (бонус) может быть опубликован в GHCR через OCI.
> **Результат сдачи:** PR из ветки `lab10`, добавляющий `k8s/lab10-app/` (чарт) и `k8s/lab10-app/HELM.md` (ваш отчёт).

---

## Обзор

В лабораторной 9 вы написали четыре голых манифеста (web Deployment + Service, echo Deployment + Service). Для одного окружения это нормально — для трёх вы бы копипастили YAML и молились, чтобы ничего не разъехалось.

Эта лабораторная вытаскивает каждое жёстко зашитое значение из этих манифестов в **чарт** с **файлом values на окружение**. Оценивается навык **написания шаблонов**: написание `Chart.yaml`, `values.yaml`, `templates/deployment.yaml`, `templates/service.yaml`, `templates/_helpers.tpl` и одного хука — с нуля. Не `helm create`-и-правь. С нуля.

> ⚠️ **Область:** никаких подчартов, библиотечных чартов, `values.schema.json`. Только анатомия чарта + иерархия values + один хук + (бонус) OCI push.

**Что вы отработаете:**
- Анатомия чарта Helm 4: `Chart.yaml`, `values.yaml`, `templates/`, `_helpers.tpl`
- Go-шаблоны + Sprig (`include`, `nindent`, `default`, `toYaml`, `printf`, `trunc`, `quote`)
- Жизненный цикл релиза: `install / upgrade / rollback / list / history / uninstall`
- Доставка в несколько окружений через иерархию values и наслоение **`-f a -f b`**
- Хуки жизненного цикла (`pre-install` / `pre-upgrade`) с весами и политиками удаления
- Публикация чартов как артефактов OCI в GHCR

> 📚 В паре с **лекцией 10 — Helm Package Management**. Перечитайте слайды 5–11 (анатомия чарта, шаблоны, `_helpers.tpl`, жизненный цикл, мульти-окружения, хуки) перед началом.

---

## Состояние проекта

**У вас должно быть из предыдущих лабораторных:**
- Кластер k3d на Kubernetes 1.36 (лабораторная 9 — `k3d cluster create devops ...`)
- Ваш **образ web из лабораторной 2** в публичном реестре (Docker Hub / GHCR)
- Манифесты из лабораторной 9 в `k8s/`: `web-deployment.yaml`, `web-service.yaml`, `echo-deployment.yaml`, `echo-service.yaml`

**Эта лабораторная добавляет:**
- `k8s/lab10-app/` — написанный вручную чарт Helm 4, который **заменяет** эти четыре манифеста
- `k8s/lab10-app/values-prod.yaml` (и опционально `-dev`, `-staging`) — различия по окружениям
- `k8s/lab10-app/templates/hooks/db-migrate.yaml` — один хук pre-install/pre-upgrade
- `k8s/lab10-app/HELM.md` — ваш отчёт о сдаче

К лабораторной 13 ArgoCD развернёт этот чарт через GitOps; к лабораторной 14 Argo Rollouts заменит шаблон Deployment, который вы напишете здесь. Так что гигиена шаблонов, которую вы выстроите на этой неделе, переживёт лабораторную 10.

---

## Настройка

```bash
helm version            # must report v4.1.x (course pins to 4.1.4)
kubectl get nodes       # your Lab 9 cluster must be up
```

> **Helm 3 vs Helm 4:** Helm 3 находится только в режиме поддержки (исправления багов до 8 июля 2026, исправления безопасности до 11 ноября 2026). Курс стандартизирован на **Helm 4**. Учтите, что `apiVersion: v2` в `Chart.yaml` по-прежнему корректен в Helm 4 — этот заголовок — версия формата чарта Helm-3-и-новее, **а не** версия бинарника Helm. `apiVersion: v1` — только для Helm 2.

Инструкции по установке: <https://helm.sh/docs/intro/install/>.

Вы напишете каждый файл в `k8s/lab10-app/` сами — **не запускайте `helm create`** (см. Частые ловушки).

---

## Задача 1 — Основы Helm и настройка (1 балл)

### 1.1 — Установите Helm 4 и изучите настоящий чарт

`ВАША ЗАДАЧА`: установите (или обновите до) Helm 4.1.x, затем вытяните метаданные и значения по умолчанию из публичного чарта, размещённого в OCI, **не устанавливая его**:

```bash
helm show chart  oci://registry-1.docker.io/bitnamicharts/nginx
helm show values oci://registry-1.docker.io/bitnamicharts/nginx | head -40
```

Посмотрите на форму: `apiVersion`, `name`, `version`, `appVersion`, `dependencies`; в `values.yaml` обратите внимание, как выставлен каждый числовой/строковый параметр.

### 1.2 — Объясните три понятия своими словами

В `HELM.md` напишите по 2–3 предложения на **Chart**, **Release**, **Values**. Не копируйте документацию — вы должны уметь ответить на них на защите. Подсказки:

- *Chart* — это пакет на диске; *Release* — один запущенный его экземпляр; *Values* заполняют шаблон.
- Helm 4 хранит состояние релиза в Secret `helm.sh/release.v1` в пространстве имён релиза (Tiller давно канул в лету — это Helm 2).

### 1.3 — Подтверждение работы

Вставьте в `HELM.md`:

- Вывод `helm version`, показывающий v4.1.x
- Первые ~20 строк одного из вызовов `helm show` выше
- Ваши объяснения Chart vs Release vs Values в 2–3 предложениях

---

## Задача 2 — Соберите чарт (3 балла)

**Цель:** написать чарт с нуля. Скелет ниже — это **форма каталогов**, которую вы должны получить. **Не** запускайте `helm create`; вы бы поставили шаблонные ссылки на `serviceaccount.yaml`, который не писали, а потом сломали бы `helm lint` в момент правки `values.yaml` (см. Частые ловушки).

```
k8s/lab10-app/
├── Chart.yaml
├── values.yaml
├── values-prod.yaml                # Task 3
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml             # web
    ├── service.yaml                # web
    ├── echo-deployment.yaml        # echo (Task 2.6)
    ├── echo-service.yaml           # echo (Task 2.6)
    ├── hooks/
    │   └── db-migrate.yaml         # Task 4
    └── NOTES.txt                   # optional; printed after install
```

### 2.1 — `Chart.yaml`

`ВАША ЗАДАЧА`: заполните метаданные. Важны и `version` (SemVer чарта — бампайте при изменениях чарта), и `appVersion` (строка версии на стороне образа — бампайте при изменениях образа); они эволюционируют независимо. `kubeVersion` заставляет Helm отказаться от установки на более старый кластер.

```yaml
apiVersion: ___                  # YOUR TASK: chart-format version (Helm 3/4 expects this value)
name: ___                        # YOUR TASK: chart name (must match the directory name)
description: ___                 # YOUR TASK: one sentence; shows in `helm show chart`
type: application                # 'application' (default) or 'library' — leave as-is for this lab
version: ___                     # YOUR TASK: SemVer for the chart, e.g. 0.1.0
appVersion: "___"                # YOUR TASK: quoted string, image-side version (your Lab 2 tag)
kubeVersion: "___"               # YOUR TASK: a range, e.g. ">=1.33.0" — refuses older clusters
# dependencies:                  # OPTIONAL — not used in this lab
#   - name: ...
#     version: ...
#     repository: ...
```

### 2.2 — `values.yaml`

`ВАША ЗАДАЧА`: перечислите каждое значение, на которое будут ссылаться ваши шаблоны, с разумным значением по умолчанию. **Каждое жёстко зашитое число/строка из манифестов лабораторной 9 становится значением здесь.** И `web`, и `echo` нуждаются в своих собственных блоках.

Минимальная поверхность (можете добавить больше):

```yaml
# YOUR TASK: fill every default. The keys below are the contract between
# values.yaml and your templates — your templates will fail to render if you
# rename a key here without updating the template, and vice versa.

replicaCount: ___                # default replicas for `web`

image:
  repository: ___                # your Lab 2 image (GHCR or Docker Hub), e.g. ghcr.io/<you>/devops-info-service
  tag: ""                        # empty → templates fall back to .Chart.AppVersion
  pullPolicy: ___                # IfNotPresent | Always | Never (Lab 9's pitfalls call out the k3d-import case)

service:
  type: ___                      # NodePort for local k3d; LoadBalancer in prod
  port: ___                      # the Service port (clients hit this)
  # the container's listen port lives under `containerPort` below

containerPort: ___               # what your Lab 2 app listens on (Lab 9 set this — match it)

resources:
  requests:
    cpu: ___
    memory: ___
  limits:
    cpu: ___
    memory: ___

probes:
  liveness:
    path: ___                    # /health from Lab 1
    initialDelaySeconds: ___
    periodSeconds: ___
  readiness:
    path: ___
    periodSeconds: ___

ingress:
  enabled: false                 # not used in this lab; reserved for Lab 16

echo:
  replicaCount: ___              # default replicas for the echo sidecar service (Lab 9 had a specific count)
  image:
    repository: ghcr.io/inno-devops-labs/echo
    tag: v1
  service:
    type: ClusterIP
    port: 80
    targetPort: 8081
  resources:                     # echo is a tiny Go binary — size it smaller than web (Lab 9 §3.1)
    requests:
      cpu: ___
      memory: ___
    limits:
      cpu: ___
      memory: ___

# Hook config (Task 4)
hooks:
  dbMigrate:
    enabled: true
    image: busybox:1.37          # any small image — the hook is a fake migration
```

### 2.3 — `templates/_helpers.tpl`

Именованные шаблоны позволяют избежать копипаста блоков labels в каждом манифесте. Вы определите **четыре**: `name`, `fullname`, `labels`, `selectorLabels`. Это мышечная память Helm; вы будете писать их в каждом чарте до конца карьеры.

`ВАША ЗАДАЧА`: реализуйте тела. Форма функции дана — заполните тело каждого блока `define` так, чтобы:

| Шаблон | Что он должен возвращать |
|---|---|
| `lab10-app.name` | Имя чарта (или `nameOverride`, если пользователь его задал), усечённое до 63 символов (лимит label в K8s) и с удалённым завершающим `-`. |
| `lab10-app.fullname` | Уникальное для релиза имя: `<release-name>-<chart-name>` (или `nameOverride`, если задан), усечённое до 63, с удалённым завершающим `-`. Именно это используют большинство полей metadata.name. |
| `lab10-app.labels` | Полный набор labels: `helm.sh/chart`, каждый label селектора (включая `selectorLabels`), `app.kubernetes.io/version`, `app.kubernetes.io/managed-by`. |
| `lab10-app.selectorLabels` | **Строгое подмножество** `labels`: только `app.kubernetes.io/name` и `app.kubernetes.io/instance`. Селекторы неизменяемы после создания — никогда не кладите сюда `version` (см. Частые ловушки). |

```handlebars
{{/* YOUR TASK: return the chart name, truncated to 63 chars, no trailing dash */}}
{{- define "lab10-app.name" -}}
{{- /* your body — hint: `default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-"` is the canonical form */ -}}
{{- end }}

{{/* YOUR TASK: return a unique-per-release name, truncated to 63, no trailing dash.
     IMPORTANT: when the release name already contains the chart name (e.g. you ran
     `helm install lab10-app k8s/lab10-app`), the canonical helper collapses to JUST
     the release name — otherwise you'd get `lab10-app-lab10-app`. Lab 11 references
     `deploy/lab10-app-web`, so your fullname helper MUST handle the collapse. The
     `helm create` boilerplate has the canonical form; cribbing the pattern (not the
     whole file) is fair game.
     Shape: `if contains $name .Release.Name → .Release.Name`, else
            `printf "%s-%s" .Release.Name $name`, then `| trunc 63 | trimSuffix "-"` */}}
{{- define "lab10-app.fullname" -}}
{{- /* your body */ -}}
{{- end }}

{{/* YOUR TASK: return the full label set (5 labels including the helm.sh/chart line) */}}
{{- define "lab10-app.labels" -}}
{{- /* your body — must include `lab10-app.selectorLabels`; emit `helm.sh/chart`,
       `app.kubernetes.io/version`, `app.kubernetes.io/managed-by` */ -}}
{{- end }}

{{/* YOUR TASK: return ONLY the two selector labels (name + instance). No version. */}}
{{- define "lab10-app.selectorLabels" -}}
{{- /* your body */ -}}
{{- end }}
```

Функции, на которые будете ссылаться (все из Sprig): `default`, `trunc`, `trimSuffix`, `printf`, `replace`, `quote`. См. [документацию Sprig](https://masterminds.github.io/sprig/) и [Chart Template Guide](https://helm.sh/docs/chart_template_guide/).

### 2.4 — `templates/deployment.yaml` (web)

`ВАША ЗАДАЧА`: превратите в шаблон ваш web Deployment из лабораторной 9. Форма YAML дана, чтобы вы не изобретали велосипед — каждый `{{ ___ }}` — это токен, который вы должны заполнить (и многие из них потребуют конвейеров вроде `| nindent 4` или `| default ...`).

> 💡 **Именуйте web и echo различно.** Оба Deployment находятся в одном релизе; если `metadata.name` разрешается в одно и то же значение на обоих, второй `helm install` завершится ошибкой конфликта. Соглашение: добавьте суффикс компонента к fullname (например, `{{ include "lab10-app.fullname" . }}-web` здесь, `-echo` в манифестах echo в 2.6). Лабораторная 11 будет ссылаться напрямую на `deploy/lab10-app-web` — сохраните суффикс.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ ___ }}-web                            # YOUR TASK: `include` your fullname template (suffix already present)
  labels:
    {{- ___ | nindent 4 }}                       # YOUR TASK: `include` your labels template
spec:
  replicas: {{ ___ }}                            # YOUR TASK: from .Values.replicaCount (with a sane default)
  selector:
    matchLabels:
      {{- ___ | nindent 6 }}                     # YOUR TASK: `include` your SELECTOR labels template
  template:
    metadata:
      labels:
        {{- ___ | nindent 8 }}                   # YOUR TASK: `include` your SELECTOR labels template
    spec:
      containers:
        - name: web
          image: "{{ ___ }}:{{ ___ | default .Chart.AppVersion }}"   # YOUR TASK: repo + tag from values
          imagePullPolicy: {{ ___ }}             # YOUR TASK: from .Values.image.pullPolicy
          ports:
            - name: http
              containerPort: {{ ___ }}           # YOUR TASK: from .Values.containerPort
              protocol: TCP
          livenessProbe:
            httpGet:
              path: {{ ___ }}                    # YOUR TASK: from values
              port: http
            initialDelaySeconds: {{ ___ }}
            periodSeconds: {{ ___ }}
          readinessProbe:
            httpGet:
              path: {{ ___ }}
              port: http
            periodSeconds: {{ ___ }}
          {{- with .Values.resources }}
          resources:
            {{- ___ | nindent 12 }}              # YOUR TASK: render the whole sub-tree as YAML (one Sprig fn)
          {{- end }}
```

> **`indent` vs `nindent`:** `nindent N` = перевод строки + отступ в N пробелов. `indent N` = только отступ. Когда действие `{{- ... -}}` стоит на своей строке и поглотило предыдущий перевод строки, `indent` даёт невалидный YAML. Используйте `nindent` в 9 случаях из 10.

### 2.5 — `templates/service.yaml` (web)

`ВАША ЗАДАЧА`: то же упражнение, гораздо короче.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ ___ }}-web                            # YOUR TASK: fullname template (`-web` suffix mirrors the Deployment)
  labels:
    {{- ___ | nindent 4 }}                       # YOUR TASK: labels template
spec:
  type: {{ ___ }}                                # YOUR TASK: from .Values.service.type
  ports:
    - port: {{ ___ }}                            # YOUR TASK: from .Values.service.port
      targetPort: http                           # named ports beat numbers; this points at the deployment's `name: http`
      protocol: TCP
      name: http
  selector:
    {{- ___ | nindent 4 }}                       # YOUR TASK: SELECTOR labels template (NOT the full labels)
```

### 2.6 — `templates/echo-deployment.yaml` + `templates/echo-service.yaml`

`ВАША ЗАДАЧА`: тот же шаблон, но для sidecar-сервиса echo. Два заметных отличия:

1. Образ берётся из `.Values.echo.image.repository` + `.Values.echo.image.tag` (без `default .Chart.AppVersion` — образ echo независим от `appVersion` вашего приложения).
2. Используйте другой дискриминатор label (например, `app.kubernetes.io/component: echo`) в шаблоне pod'а + селекторе Service, чтобы Service **web** случайно не выбирал pod'ы echo. Вы можете либо:
   - Расширить ваш хелпер `selectorLabels` опциональным компонентом (передав `.Values.echo` в `include`), **либо**
   - Вручную написать небольшой дополнительный ключ селектора только в этом манифесте.

Подумайте минуту, какой выбрать — оба допустимы.

### 2.7 — Проверьте, отрендерьте, установите

Запустите по порядку: `helm lint <chart>`, `helm template <release> <chart>` (просмотрите отрендеренный YAML), `helm install <release> <chart> --dry-run --debug`, затем настоящий `helm install --create-namespace` в свежее пространство имён. Завершите `helm list` (ожидайте `REVISION 1`) и `kubectl get deploy,svc,pods`, чтобы подтвердить, что оба pod'а Ready.

```bash
# Release name MUST be `lab10-app` (matches chart name). Lab 11 references `deploy/lab10-app-web`;
# if your fullname helper has the canonical collapse-when-contained branch (see 2.3), this works.
# If you used a too-simple fullname (just `printf "%s-%s" .Release.Name .Chart.Name`), you'll get
# `lab10-app-lab10-app-web` and Lab 11 won't find your Deployment. Run `helm template` first to verify.
helm install lab10-app k8s/lab10-app -n helm-demo --create-namespace
# expected: helm list shows STATUS deployed, REVISION 1
# expected (verify with `kubectl get deploy -n helm-demo`): deploy/lab10-app-web and deploy/lab10-app-echo
```

### 2.8 — Подтверждение работы

Вставьте в `HELM.md`:

- Вывод `helm lint k8s/lab10-app` (должен сказать `0 chart(s) failed`)
- Первые ~30 строк `helm template lab10-app k8s/lab10-app`, показывающие, как ваши значения попадают в отрендеренный Deployment (образ, реплики, пробы, ресурсы)
- `helm list -n helm-demo`, показывающий **REVISION 1** для релиза `lab10-app`
- `kubectl get deploy,svc,pods -n helm-demo`, показывающий pod'ы web и echo Ready (имена deploy: `lab10-app-web`, `lab10-app-echo`)

---

## Задача 3 — Values для нескольких окружений (3 балла)

**Цель:** управлять ≥ 2 окружениями из одного чарта, используя иерархию base + override.

### 3.1 — Создайте `values-prod.yaml` (и опционально `values-dev.yaml` / `values-staging.yaml`)

`ВАША ЗАДАЧА`: напишите файл override **только с различиями** — только ключи, которые отличаются от `values.yaml`. Предлагаемая форма:

| | dev (значения по умолчанию в `values.yaml`) | prod (`values-prod.yaml`) |
|---|---|---|
| `replicaCount` | 1 | 4 |
| `image.tag` | `""` (→ `appVersion`) | закреплённый SemVer, например `v1.2.0` |
| `service.type` | `NodePort` | `LoadBalancer` |
| `resources.requests.cpu` | `100m` | `500m` |
| `resources.limits.memory` | `256Mi` | `1Gi` |

Для ≥ 3 окружений добавьте `values-staging.yaml` между ними.

### 3.2 — Обновите существующий релиз с наслоённой иерархией values

Это **главное доказательство** задачи 3 — тот же чарт, тот же релиз, переход с REVISION 1 на REVISION 2 потому, что `-f` наслоил prod-override поверх базы.

```bash
helm upgrade lab10-app k8s/lab10-app -n helm-demo \
  -f k8s/lab10-app/values.yaml \
  -f k8s/lab10-app/values-prod.yaml
# expected: STATUS deployed, REVISION 2
# expected: deploy/lab10-app-web spec.replicas = your prod override (was 1 at REV 1)
```

Затем запустите `helm list`, `kubectl get deploy lab10-app-web -n helm-demo -o jsonpath='{.spec.replicas}'` и `helm history`, чтобы зафиксировать доказательства.

> **Приоритет values (от низшего → высшего):**
> 1. `values.yaml` (по умолчанию чарта, **загружается всегда** — его не нужно передавать явно)
> 2. Каждый `-f file.yaml` по порядку — более поздние файлы переопределяют более ранние
> 3. `--set key=value` в CLI
>
> Так что `-f values.yaml -f values-prod.yaml --set replicaCount=10` завершится с 10 репликами.

### 3.3 — Отрендерьте разницу по окружениям без кластера

`ВАША ЗАДАЧА`: используйте `helm template` против чарта **без** и **с** `-f values-prod.yaml`, затем `diff` два вывода. Видимая разница — ваше доказательство, что файл override что-то сделал — кластер не нужен. Зафиксируйте первые ~20 строк diff в `HELM.md`.

### 3.4 — Откат

`ВАША ЗАДАЧА`: `helm rollback lab10-app 1 -n helm-demo`, затем снова запросите число реплик у deployment — оно должно вернуться к значению dev по умолчанию. Зафиксируйте `helm history`, показывающий REVISION 3 с описанием отката.

### 3.5 — Подтверждение работы

Вставьте в `HELM.md`:

- Содержимое `values-prod.yaml` (только различия — должно быть коротко)
- `helm list -n helm-demo` **на REVISION 2**, снятый после обновления
- `kubectl get deploy lab10-app-web -n helm-demo -o jsonpath='{.spec.replicas}'`, возвращающий prod-значение
- `helm history lab10-app -n helm-demo`, показывающий, что REVISION 1 заменён REVISION 2
- Первые 20 строк `diff` из 3.3 — видимую разницу между отрендеренными окружениями

---

## Задача 4 — Хуки жизненного цикла (2 балла)

**Цель:** добавьте **один** хук Job, который запускается на `pre-install` И `pre-upgrade` (например, фиктивная миграция БД), упорядоченный через `hook-weight` и очищаемый через `hook-delete-policy`.

### 4.1 — Напишите `templates/hooks/db-migrate.yaml`

Четыре ключа аннотаций — это весь контракт хука, остальное — обычный Job `batch/v1`. `ВАША ЗАДАЧА`: напишите файл. Скелет:

```yaml
{{- if .Values.hooks.dbMigrate.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ ___ }}-db-migrate                  # YOUR TASK: fullname template + "-db-migrate"
  labels:
    {{- ___ | nindent 4 }}                    # YOUR TASK: labels template
  annotations:
    "helm.sh/hook": ___                       # YOUR TASK: TWO comma-separated points — pre-install,pre-upgrade
    "helm.sh/hook-weight": "___"              # YOUR TASK: a string, NOT a number (Helm quirk). Negative runs earlier.
    "helm.sh/hook-delete-policy": ___         # YOUR TASK: comma-separated policies — before-hook-creation,hook-succeeded
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: db-migrate
          image: {{ ___ }}                    # YOUR TASK: from .Values.hooks.dbMigrate.image
          command: ["sh", "-c"]
          args:
            - |
              echo "running pre-install/pre-upgrade migration for release {{ .Release.Name }}";
              sleep 5;
              echo "migration complete";
{{- end }}
```

**Четыре ключа аннотаций**, которые вы должны задать (и что они делают):

| Аннотация | Требуемое значение здесь | Что она делает |
|---|---|---|
| `helm.sh/hook` | `pre-install,pre-upgrade` | Когда запускать. Через запятую для нескольких точек. |
| `helm.sh/hook-weight` | Строка в кавычках вроде `"-5"` | Порядок среди хуков в одной точке. Меньшее значение запускается первым; при равенстве — по алфавиту. **Должно быть строкой в кавычках** — Helm парсит её как строку и конвертирует внутри. |
| `helm.sh/hook-delete-policy` | `before-hook-creation,hook-succeeded` | Когда удалять ресурс хука. Без этого неудачные Job'ы копятся навсегда — `helm uninstall` НЕ удаляет ресурсы хуков. |
| (нет — ресурс и есть сам Job) | — | Хук — это обычный Job, просто не часть регулярного релиза. |

### 4.2 — Проверьте, что хук срабатывает на install И upgrade

`ВАША ЗАДАЧА`: удалите релиз для чистого старта, затем установите заново. Во время установки запустите `kubectl get jobs -n helm-demo` (Job хука должен появиться) и `kubectl logs job/<hook-job>`, чтобы зафиксировать ваш echo `running pre-install migration`. Затем сделайте `helm upgrade` с `-f values-prod.yaml` и подтвердите, что **тот же хук срабатывает снова** на `pre-upgrade`. Наконец, снова запросите jobs — `before-hook-creation,hook-succeeded` должны были удалить предыдущий.

### 4.3 — Подтверждение работы

Вставьте в `HELM.md`:

- Блок аннотаций вашего `db-migrate.yaml` (контракт из четырёх ключей)
- `kubectl get jobs -n helm-demo`, снятый **во время** установки (Job присутствует)
- `kubectl logs` из Job хука, показывающий ваш echo "running pre-install migration"
- `kubectl get jobs -n helm-demo`, снятый **после** срабатывания политики (Job исчез)

---

## Задача 5 — Документация (1 балл)

`ВАША ЗАДАЧА`: создайте `k8s/lab10-app/HELM.md`, охватывающий по порядку:

1. **Обзор чарта** — дерево каталогов, что рендерит каждый шаблон, контракт `values.yaml`
2. **Конфигурация** — таблица значений верхнего уровня и чем `values-prod.yaml` отличается от умолчаний
3. **Хелперы** — ваши четыре именованных шаблона и одно предложение о том, почему `selectorLabels` — подмножество `labels`
4. **Хук** — четыре аннотации на вашем Job `db-migrate` и что делает каждая
5. **Операции** — точные команды `install`, `upgrade -f a -f b`, `history`, `rollback`, `uninstall`, которые вы выполняли
6. **Доказательства** — все скриншоты из задач 1.3 / 2.8 / 3.5 / 4.3
7. **Трудности и выводы** — хотя бы одна настоящая (баг `indent`/`nindent`, неизменяемый селектор, `hook-weight` без кавычек и т.п.)

---

## Бонусная задача — Публикация в GHCR через OCI (2 балла)

**Цель:** упакуйте чарт, запушьте его в GHCR как артефакт OCI, затем **установите его из реестра**, чтобы доказать round-trip.

`ВАША ЗАДАЧА`: здесь меньше подсказок.

1. `helm package` ваш чарт в `lab10-app-<version>.tgz`.
2. Создайте **classic** PAT GitHub (Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token) с областью **`write:packages`**. Fine-grained token'ы пока не поддерживают OCI push (май 2026). В CI вы бы использовали автоинжектируемый `GITHUB_TOKEN`; локально используйте PAT. **Никогда не вставляйте PAT в закоммиченный файл или в CLI.**
3. `echo $CR_PAT | helm registry login ghcr.io -u <your-username> --password-stdin` — PAT приходит через stdin, чтобы не попасть в историю оболочки.
4. `helm push <tgz> oci://ghcr.io/<your-username>/charts`.
5. Сделайте пакет GHCR **публичным** (Your profile → Packages → `charts/lab10-app` → Package settings → Change visibility → Public), чтобы проверяющий мог вытянуть его без учётных данных.
6. В свежем пространстве имён выполните `helm install … oci://ghcr.io/<your-username>/charts/lab10-app --version <ver>` — и докажите, что установка пришла **из реестра**, а не из вашего локального каталога (в `STATUS` будет виден OCI-источник).

Команды, которые понадобятся (ищите их — `helm package`, `helm registry login`, `helm push`, `helm install oci://...`).

Вставьте в `HELM.md`:

- Вывод `helm package`
- Вывод `helm push` **с digest**
- URL пакета GHCR (например, `https://github.com/users/<you>/packages/container/package/charts%2Flab10-app`)
- Вывод `helm install oci://…` и `helm list`, показывающий релиз из OCI-источника

---

## Как сдавать

Тот же поток, что в лабораторной 9: ветка `lab10`, добавьте `k8s/lab10-app/`, закоммитьте, запушьте, откройте **два** PR.

```bash
git switch -c lab10
git add k8s/lab10-app/
git commit -m "feat(lab10): package web + echo as a helm 4 chart"
git push -u origin lab10
```

PR:

- `your-fork:lab10` → `course-repo:master` *(на проверку)*
- `your-fork:lab10` → `your-fork:master` *(сливается в ваш собственный main, когда готово)*

Чек-лист PR:

```text
- [ ] Task 1 done — helm v4.1.x, public chart inspected, concepts explained
- [ ] Task 2 done — Chart.yaml, values.yaml, _helpers.tpl (4 templates), deployment + service + echo manifests, lint clean, REVISION 1 installed
- [ ] Task 3 done — values-prod.yaml + `helm upgrade -f base -f override` → REVISION 2 with replica count change
- [ ] Task 4 done — pre-install/pre-upgrade hook with the four annotations, hook fires + cleans up
- [ ] Task 5 done — HELM.md with all seven sections + evidence
- [ ] Bonus done — chart pushed to GHCR via OCI and installed from the registry
```

---

## Критерии приёмки

### Задача 1 (1 балл)
- ✅ `helm version` показывает v4.1.x
- ✅ Публичный OCI-чарт изучен через `helm show chart` / `helm show values`
- ✅ Chart / Release / Values объяснены своими словами

### Задача 2 (3 балла)
- ✅ `Chart.yaml` с корректными `apiVersion`, SemVer `version` и `appVersion`
- ✅ `values.yaml` с каждым жёстко зашитым значением из лабораторной 9 (реплики, образ, порты, ресурсы, пробы, блок echo)
- ✅ `_helpers.tpl` определяет и использует **четыре** именованных шаблона: `name`, `fullname`, `labels`, `selectorLabels`
- ✅ `selectorLabels` — строгое подмножество `labels` (без `version`)
- ✅ Все четыре шаблона манифестов рендерятся через `include`, `nindent`, `default`, `with`
- ✅ Пробы liveness + readiness сохранены и настраиваемы через values
- ✅ `helm lint` чист и `helm install` достигает REVISION 1

### Задача 3 (3 балла)
- ✅ `values-prod.yaml` (и опционально dev/staging) содержит **только различия** от `values.yaml`
- ✅ `helm upgrade ... -f values.yaml -f values-prod.yaml` даёт REVISION 2
- ✅ Реальное значение (число реплик) видимо меняется между ревизиями
- ✅ `helm rollback` возвращает релиз к REVISION 1

### Задача 4 (2 балла)
- ✅ Один хук Job с `helm.sh/hook: pre-install,pre-upgrade`
- ✅ Задан `helm.sh/hook-weight` (строка в кавычках)
- ✅ Задан `helm.sh/hook-delete-policy`, чтобы Job очищался
- ✅ Хук срабатывает и на install, и на upgrade; логи зафиксированы

### Задача 5 (1 балл)
- ✅ `HELM.md` охватывает все семь обязательных разделов со вставленными скриншотами

### Бонус (2 балла)
- ✅ Чарт упакован в `.tgz`
- ✅ Запушен в `oci://ghcr.io/<username>/charts`
- ✅ Установлен *из реестра* (не из локального каталога)
- ✅ URL GHCR + вывод установки из OCI в `HELM.md`

---

## Рубрика

| Задача | Баллы | Критерии |
|------|-------:|----------|
| **Задача 1** — Основы | **1** | v4.1.x, публичный чарт изучен, понятия объяснены |
| **Задача 2** — Сборка чарта | **3** | Чистое шаблонизирование, четыре хелпера, lint чист, install достигает REVISION 1 |
| **Задача 3** — Мульти-окружения | **3** | Наслоение `-f a -f b` даёт REVISION 2 с видимым изменением значения; откат работает |
| **Задача 4** — Хуки | **2** | Хук pre-install/pre-upgrade с weight + delete policy; срабатывает и очищается |
| **Задача 5** — Документация | **1** | Полный `HELM.md` с доказательствами |
| **Бонус** — OCI push | **2** | Чарт упакован, запушен в GHCR, установлен *из реестра* |
| **Итого** | **12** | 10 основных + 2 бонусных |

**Оценивание:**
- **10/10:** Чистое шаблонизирование с нуля, мульти-окруженческое обновление видно по ревизиям, хук срабатывает + очищается, основательная документация
- **8–9/10:** Чарт устанавливается и обновляется, небольшие пробелы в хелперах или аннотациях хука
- **6–7/10:** Базовый чарт устанавливается, но мульти-окруженческое обновление или доработка хука отсутствуют
- **<6/10:** Сдан шаблон `helm create`, жёстко зашитые значения, нет хука, или чарт не проходит lint

---

## Ресурсы

<details>
<summary>📚 Документация</summary>

- [Helm Documentation](https://helm.sh/docs/) — Helm 4
- [Chart Template Guide](https://helm.sh/docs/chart_template_guide/)
- [Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Chart Hooks](https://helm.sh/docs/topics/charts_hooks/)
- [Use OCI-based registries](https://helm.sh/docs/topics/registries/)
- [Sprig function reference](https://masterminds.github.io/sprig/) — the function library you'll consult weekly
- [Built-in Objects](https://helm.sh/docs/chart_template_guide/builtin_objects/) — `.Release`, `.Chart`, `.Values`, `.Files`, `.Capabilities`

</details>

<details>
<summary>🛠️ Инструменты и реестры</summary>

- [Artifact Hub](https://artifacthub.io/) — public chart search (15,000+ charts)
- [helm-docs](https://github.com/norwoodj/helm-docs) — auto-generate README from values
- [chart-testing](https://github.com/helm/chart-testing) — lint & install charts in CI
- [GHCR](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) — OCI registry for both images and charts

</details>

<details>
<summary>⚠️ Частые ловушки (из реальных прогонов)</summary>

- **`helm create` затирает вашу работу.** Запуск его внутри существующего каталога чарта перезаписывает ваш написанный вручную `Chart.yaml`, `values.yaml` и хелперы без вопросов. Не запускайте его. Пишите файлы сами — эта лабораторная оценивает именно этот навык.
- **В fullname-хелпере отсутствует ветка схлопывания.** Наивное `printf "%s-%s" .Release.Name .Chart.Name` даёт `lab10-app-lab10-app`, когда имя релиза и имя чарта совпадают (а они совпадают — релиз это `lab10-app`). Затем `-web` дописывается, давая `lab10-app-lab10-app-web`. Лабораторная 11 ссылается на `deploy/lab10-app-web`, так что это молча ломает следующую лабораторную. Каноническая ветка `if contains $name .Release.Name` (срисованная из `helm create`) — это то, что делает схлопывание рабочим. Проверьте через `helm template lab10-app k8s/lab10-app | grep '^  name:'` ДО установки.
- **Замена всего `helm create` `values.yaml` ломает `helm lint`.** Сгенерированный шаблон поставляет `templates/serviceaccount.yaml`, который ссылается на `.Values.serviceAccount.create`. В момент, когда вы стираете этот блок в `values.yaml`, `helm lint` завершается ошибкой, потому что исчез ключ, на который ссылаются. Либо правьте значения по умолчанию на месте, **либо** (рекомендуется) вообще пропустите `helm create`. *(Это та самая самостоятельно созданная заминка из собственного эталонного прогона лабораторной.)*
- **`indent` vs `nindent`.** `nindent N` = перевод строки + N пробелов; `indent N` = только N пробелов. Когда действие `{{- ... -}}` уже съело предыдущий перевод строки, `indent` даёт невалидный YAML, который поймает `helm lint`, а `helm install` откажется выполнять. Используйте `nindent`, если не уверены.
- **Изменяемые labels селектора ломают раскатку.** Как только `Deployment` существует, K8s отклоняет изменения `spec.selector.matchLabels`. Если `version` в ваших labels селектора, каждый бамп `appVersion` запускает обновление чарта, которое K8s отклоняет — вам придётся `kubectl delete deploy ...` и потерять нулевой простой. Держите `selectorLabels` только с `name` + `instance`.
- **`hook-weight` должен быть строкой в кавычках.** `"helm.sh/hook-weight": -5` (без кавычек) молча парсится как число, и Helm его игнорирует; вы получите недетерминированный порядок хуков. Всегда берите в кавычки: `"helm.sh/hook-weight": "-5"`.
- **Ресурсы хуков переживают `helm uninstall`.** Job'ы хуков — *не* часть релиза. Без `hook-delete-policy` неудачные Job'ы копятся навсегда, и `helm uninstall` не удалит их. Всегда задавайте `before-hook-creation,hook-succeeded`.
- **Забыли `helm dependency update` после правки `Chart.yaml`.** Если вы добавите запись `dependencies:` (не требуется в этой лабораторной, но легко добавить для бонуса), подчарт не загрузится в `charts/`, пока вы не запустите `helm dependency update`. Затем `helm install` падает с запутанно сформулированной ошибкой отсутствующей зависимости.
- **Подвох с OCI-аутентификацией.** `helm registry login ghcr.io` использует конфиг Docker, а не отдельное хранилище учётных данных Helm. Если для `ghcr.io` существует устаревший docker login, возможно, понадобится сначала `docker logout ghcr.io`. Всегда передавайте PAT через `--password-stdin`; никогда не кладите его в командную строку (он попадёт в историю оболочки).
- **`apiVersion: v2` vs `v1` в `Chart.yaml`.** `v2` — версия формата чарта, введённая Helm 3 и по-прежнему используемая Helm 4 — **не** версия бинарника Helm. `v1` — только для Helm 2. Helm 4 против чарта `v1` падает сразу; Helm 3 против чарта `v2` работает. Всегда пишите `apiVersion: v2`.
- **Пустой `image.tag` в `values.yaml`.** Установка `tag: ""` позволяет `{{ .Values.image.tag | default .Chart.AppVersion }}` откатиться. Установка `tag: latest` убивает воспроизводимость (ломает откаты и ломает diff в ArgoCD в лабораторной 13). Оставляйте пустым в умолчаниях; закрепляйте SemVer в `values-prod.yaml`.

</details>

<details>
<summary>📖 Учебные ресурсы</summary>

- [Quickstart Guide](https://helm.sh/docs/intro/quickstart/)
- [Using Helm](https://helm.sh/docs/intro/using_helm/)
- [Three Big Concepts](https://helm.sh/docs/intro/using_helm/#three-big-concepts)
- *Learning Helm* (2e, 2024) — Butcher, Farina, Dolitsky (O'Reilly)

</details>

---

## Взгляд вперёд

| Лабораторная | Что добавляет к этому чарту |
|---:|---|
| 11 | Управление секретами с OpenBao — потому что `values.yaml` отслеживается в git, а ваш пароль БД — нет |
| 12 | ConfigMaps + PVC, добавленные как новые шаблоны в этот же чарт |
| 13 | ArgoCD развёртывает этот чарт через GitOps; `helm template` становится шагом рендеринга |
| 14 | Argo Rollouts заменяет шаблон Deployment на Rollout для canary-доставки |
| 16 | kube-prometheus-stack (сам являющийся чартом Helm) собирает метрики вашего приложения через ServiceMonitor, который вы добавите в этот чарт |

---

**Удачи!** ⛵

> **Помните:** шаблонизируйте всё, не зашивайте ничего жёстко (кроме разумных умолчаний в `values.yaml`). Один чарт, N файлов values. Никогда не закомментируйте проверку состояния — сделайте её значением. И **никогда** не запускайте `helm create` в этой лабораторной.
