# Лабораторная работа 12 — ConfigMaps и постоянные тома

![difficulty](https://img.shields.io/badge/difficulty-intermediate-yellow)
![topic](https://img.shields.io/badge/topic-Configuration%20%26%20Storage-blue)
![points](https://img.shields.io/badge/points-10%2B2-orange)
![tech](https://img.shields.io/badge/tech-ConfigMaps%20%7C%20PVC%20%7C%20K8s%201.36-informational)

> **Цель:** вынести неконфиденциальную конфигурацию в ConfigMaps и сделать данные приложения переживающими `kubectl delete pod` с помощью PersistentVolumeClaim.
> **Результат сдачи:** PR из ветки `lab12`, расширяющий ваш чарт из лабораторных 10/11 двумя ConfigMap + PVC, счётчиком визитов на стороне приложения и `docs/LAB12.md`, содержащим доказательство персистентности «запись-удаление-pod-чтение-из-нового-pod'а».

---

## Обзор

Лабораторная 11 спрятала ваши *секреты* (пароли БД, API-токены). Но не каждое значение секретно — уровни логирования, фича-флаги, имена приложений, конфиги `NGINX` — это относится к **ConfigMaps**. А контейнеры *эфемерны*: при перезапуске pod'а его записываемый слой исчезает. Всё, что ваше приложение записало на локальный диск, пропадает. Решение — **PersistentVolumeClaim** — pod претендует на хранилище по имени, том следует за pod'ом с одного узла на другой, а данные переживают любой отдельный pod.

В этой лабораторной работе вы отработаете:

- Три паттерна инъекции ConfigMap (одна env, массово через `envFrom`, монтирование тома) и **выбор правильного для ситуации**
- Проектирование PVC: режим доступа, размер, класс хранилища — **читая то, что реально предлагает кластер**, а не угадывая
- Главное доказательство: **запись → `kubectl delete pod` → чтение из нового pod'а → то же значение**. PVC, который просто стал `Bound`, НЕ доказывает персистентность.

> ⚠️ **Область:** одна реплика с хранилищем `ReadWriteOnce`. `ReadWriteMany` (параллельные записи с нескольких узлов) требует сетевой ФС (NFS/EFS/CephFS) и вне этой лабораторной. StatefulSets + `volumeClaimTemplates` (один PVC на реплику) придут в лабораторной 15.

---

## Состояние проекта

**У вас должно быть из предыдущих лабораторных:**
- Лабораторная 9 — ваш Deployment `web` + Service на k3d (1.36)
- Лабораторная 10 — ваш чарт Helm `lab10-app`, упаковывающий этот Deployment + Service
- Лабораторная 11 — Secret(ы), подключённые к тому же чарту

**Эта лабораторная добавляет (в ваш существующий чарт):**
- **Счётчик визитов** на стороне приложения, пишущий в файл под `DATA_DIR` (по умолчанию `/data`)
- `templates/configmap.yaml` — два ConfigMap; один монтируется как файл, другой массово инжектируется как переменные окружения
- `templates/pvc.yaml` — PVC под `.Values.persistence.enabled`
- Патчи Deployment для их подключения
- `docs/LAB12.md` — доказательство персистентности + ваши рассуждения о дизайне

> 📚 В паре с **лекцией 12 — ConfigMaps and Persistent Volumes**. Перечитайте слайды 6–8 (паттерны инъекции), 13–15 (PV/PVC/StorageClass, режимы доступа, политики возврата) и 16 (ловушка `subPath`) перед началом.

---

## Настройка

Вам нужен кластер k3d из лабораторной 9 на Kubernetes 1.36, ваш чарт `lab10-app` и `kubectl`.

```bash
kubectl get nodes                # should show k3d-devops-server-0 + 2 agents on v1.36.x
helm list -n lab12 2>/dev/null   # namespace you'll use below
```

**Прежде чем написать хоть строку YAML**, изучите, что кластер даёт вам бесплатно — ответы на «какой режим доступа?» и «какой класс хранилища?» зависят от этого:

```bash
kubectl get storageclass
# YOUR TASK: read the output. Which one has the (default) marker? What provisioner backs it?
# Write the answer in docs/LAB12.md — this is the storage class your PVC will use.
```

> 💡 k3d (k3s) поставляет **`local-path`** (`rancher.io/local-path`) с пометкой `(default)`. Он только RWO, без снапшотов — нормально для счётчика визитов на одном pod'е, но не то, что вы бы запускали в проде. На реальном облачном кластере тот же чарт привязался бы к тому **AWS EBS** (`ebs.csi.aws.com`) или **GCE PD** (`pd.csi.storage.gke.io`) через его CSI-драйвер, без изменений чарта.

---

## Задача 1 — Апгрейд персистентности приложения (2 балла)

Прежде чем любая работа с Kubernetes, приложению нужно что-то, что стоит сохранять. Добавьте счётчик визитов, пишущий в файл, и докажите, что он работает локально, прежде чем двигаться дальше.

### 1.1 — Добавьте счётчик визитов

`ВАША ЗАДАЧА`: в `app_python/app.py` (или эквиваленте на вашем языке) добавьте счётчик.

Требования:

- `GET /` инкрементирует счётчик; значение хранится в файле под `DATA_DIR` (переменная окружения, по умолчанию `/data`).
- При старте прочитайте файл. Если его нет, по умолчанию `0` — не падайте.
- Добавьте `GET /visits`, возвращающий JSON `{"visits": N}`.
- Пишите **атомарно**: пишите во временный файл в том же каталоге, затем `os.replace(tmp, final)`. Сбой посреди записи не должен испортить счётчик.
- Создайте каталог данных при старте, если его нет (`os.makedirs(..., exist_ok=True)`).

Подсказки — набросок движущихся частей (НЕ копируйте, выведите код сами):

- **константы** — `DATA_DIR = env("DATA_DIR","/data")`, `COUNTER = DATA_DIR + "/visits"`
- **read_count** — открыть + `int(...)`; при `FileNotFoundError` вернуть `0`
- **write_count(n)** — `mkstemp` в `DATA_DIR` → запись → `os.replace(tmp, COUNTER)` (атомарно)
- **`GET /`** — `c = read_count() + 1`; `write_count(c)`; ответ
- **`GET /visits`** — ответ `{ "visits": read_count() }`

### 1.2 — Локальный тест персистентности в Docker Compose

`ВАША ЗАДАЧА`: в `app_python/docker-compose.yml` смапьте каталог хоста на `DATA_DIR`. Ударьте по `/` три раза, перезапустите контейнер, ударьте по `/visits` — счётчик должен продолжиться, а не сброситься.

Скелет (заполните пропуски):

```yaml
services:
  app:
    # ... your build/image from Lab 2 ...
    environment:
      DATA_DIR: # YOUR TASK
    volumes:
      - # YOUR TASK: host-path : DATA_DIR
```

### 1.3 — Подтверждение работы

Вставьте в `docs/LAB12.md`:

- Три curl (`curl localhost:8080/` × 3) + чтение `/visits`.
- `docker compose restart app` с последующим `/visits`, показывающим **то же** число, а не 0.
- `cat ./data/visits` с хоста, показывающий то же целое число (доказывает, что данные действительно сохранены, а не гонка).

---

## Задача 2 — ConfigMaps: три паттерна, одно решение на значение (3 балла)

Лекция охватила три способа инъекции ConfigMap в pod. **Один паттерн на *значение* — не все три для каждого значения.** Вы поставите два ConfigMap (один в форме файлов, один в форме переменных окружения), подключите каждый в pod паттерном, подходящим его форме, и обоснуете выбор для трёх примеров значений в таблице решений ниже.

### 2.1 — Напишите два ConfigMap

Вы поставите два ConfigMap в `templates/configmap.yaml`. Форма и *labels* даны; **данные** — ваши, заполните их из `values.yaml` чарта.

Скелет — `templates/configmap.yaml` (один файл, два CM, разделённые `---`):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "lab10-app.fullname" . }}-file
  labels: {{- include "lab10-app.labels" . | nindent 4 }}
data:
  config.json: |-                # YOUR TASK: load files/config.json via .Files.Get
                                 #            and indent 4 — hint: `| indent 4`
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "lab10-app.fullname" . }}-env
  labels: {{- include "lab10-app.labels" . | nindent 4 }}
data:                            # YOUR TASK: ≥3 K/V pairs from .Values
                                 # ⚠️ keys must match [A-Z_][A-Z0-9_]* (Lec 12 slide 7)
                                 # invalid names are silently skipped by envFrom
```

`ВАША ЗАДАЧА`: создайте `files/config.json` как минимум с этими ключами: `appName`, `environment`, `features` (объект с `visitsCounter: true`). Добавьте соответствующие значения в `values.yaml`.

### 2.2 — Выберите паттерн инъекции на значение

Существуют три паттерна инъекции (лекция 12, слайды 6–8). Ниже скелет каждого как отдельного блока-патча Deployment — **оставьте нужные, удалите остальные**, затем обоснуйте свой выбор в `docs/LAB12.md`. Как минимум ваш Deployment должен использовать паттерн B (CM в форме env) **и** паттерн C (CM в форме файла); паттерн A опционален и приносит баллы, только если вы можете обосновать конкретную причину переименовать или выбрать единственный ключ.

**Паттерн A — одна env, переименованная/опциональная.** Используйте, когда нужно ОДНО значение, возможно ПЕРЕИМЕНОВАННОЕ в контейнере.

```yaml
env:
  - name:                            # YOUR TASK: env name inside the container
    valueFrom:
      configMapKeyRef:
        name:                        # YOUR TASK: which of your two ConfigMaps holds this?
        key:                         # YOUR TASK: key in the ConfigMap (may differ from name)
        optional:                    # YOUR TASK: true/false — start if missing?
```

**Паттерн B — `envFrom` (массово).** КАЖДЫЙ ключ в CM становится переменной окружения. Без переименования, без фильтра — курируйте ConfigMap, а не инъекцию.

```yaml
envFrom:
  - configMapRef:
      name:                          # YOUR TASK
```

**Паттерн C — монтирование тома (весь каталог, НЕ `subPath`).** Для структурированных файлов (JSON/YAML/conf), которые читает приложение; автообновление без пересборки образа (от этого зависит бонус).

```yaml
volumeMounts:
  - name:                            # YOUR TASK: must match the volume name below
    mountPath:                       # YOUR TASK: dir where config.json appears
                                     # ⚠️ NO subPath: here — see Bonus + Pitfalls
volumes:
  - name:                            # YOUR TASK: same name as the volumeMount above
    configMap:
      name:                          # YOUR TASK: which ConfigMap supplies the files?
```

Выберите правильный паттерн для каждого из этих значений и задокументируйте выбор в `docs/LAB12.md` (по одному предложению на каждое):

| Значение | Паттерн? | Почему? |
|---|---|---|
| `LOG_LEVEL` (одна строка, которую фреймворк читает из env) | YOUR TASK | YOUR TASK |
| `config.json` (структурированный файл с фича-флагами) | YOUR TASK | YOUR TASK |
| ≥ 10 булевых фича-флагов, которые все должны быть env-переменными | YOUR TASK | YOUR TASK |

> 💡 **Подсказка** — ни один из трёх ответов не «все три». Одно значение — один паттерн. Смысл в *решении*, а не в размножении.

### 2.3 — Подтверждение работы

`ВАША ЗАДАЧА`: после `helm upgrade --install lab10-app k8s/lab10-app -n lab12 --create-namespace` (тот же путь чарта, что в лабораторных 10/11) зафиксируйте:

```bash
# YOUR TASK: get the pod name into $POD
# YOUR TASK: cat the mounted config.json from inside the pod — shows file mount works
# YOUR TASK: printenv | grep -E '<your env keys>' — shows env injection works
# YOUR TASK: kubectl describe pod $POD | grep -A2 -E 'Environment|Mounts' — shows the wiring
```

Вставьте в `docs/LAB12.md`:

- Три скриншота выше (содержимое файла, переменные окружения, фрагмент describe pod'а)
- Заполненную таблицу решений из 2.2
- Один абзац: *если бы в ConfigMap было 30 ключей, а вам нужны только 2, вы бы всё равно использовали `envFrom`? Почему/почему нет?*

---

## Задача 3 — Постоянные тома: прочитайте кластер, затем напишите claim (3 балла)

У PVC есть четыре ручки: `accessModes`, `resources.requests.storage`, `storageClassName` и (менее очевидно) **политика возврата**, наследуемая от StorageClass. Вы зададите первые три явно — но только после изучения того, что кластер уже предлагает.

### 3.1 — Сначала изучите хранилище кластера

```bash
kubectl get storageclass
kubectl get sc <default-sc-name> -o yaml | grep -E 'provisioner|reclaimPolicy|volumeBindingMode'
```

`ВАША ЗАДАЧА`: в `docs/LAB12.md` ответьте:

- У какого StorageClass маркер `(default)`? Какой провайдер его обеспечивает?
- Какова его `reclaimPolicy` (Delete vs Retain)? Что произойдёт с вашими данными, если удалить PVC?
- Каков его `volumeBindingMode`? Почему `WaitForFirstConsumer` означает, что PVC в `Pending` — **норма**, а не баг?

### 3.2 — Выберите `accessModes` для случая со счётчиком визитов

Четыре режима (лекция 12, слайд 14):

- **`ReadWriteOnce`** — RW с одного *узла* (несколько pod'ов на этом узле — можно). Облачное блочное хранилище (EBS/PD/Azure Disk) поддерживает только это.
- **`ReadOnlyMany`** — RO со многих узлов. Распространение контента.
- **`ReadWriteMany`** — RW со многих узлов одновременно. Нужны NFS/EFS/CephFS — медленнее, дороже.
- **`ReadWriteOncePod`** — RW ровно с *одного* pod'а в масштабе кластера (GA в K8s 1.29).

`ВАША ЗАДАЧА`: выберите ОДИН для счётчика визитов и обоснуйте его в `docs/LAB12.md`. Подсказка: у вас одна реплика Deployment, пишущая в один файл. Не тянитесь к самому гибкому варианту — тянитесь к тому, что реально подходит.

### 3.3 — Напишите PVC

Скелет — `templates/pvc.yaml`:

```yaml
{{- if .Values.persistence.enabled }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "lab10-app.fullname" . }}-data
  labels: {{- include "lab10-app.labels" . | nindent 4 }}
spec:
  accessModes:
    -                              # YOUR TASK: RWO | ROX | RWX | RWOP — pick + defend
  resources:
    requests:
      storage:                     # YOUR TASK: size — counter is one int, don't ask 100Gi
  {{- with .Values.persistence.storageClass }}
  storageClassName: {{ . }}        # omit field → cluster default; "" → also default
  {{- end }}
{{- end }}
```

Добавьте в `values.yaml`:

```yaml
persistence:
  enabled: true
  size: # YOUR TASK
  storageClass: # YOUR TASK: "" to use the cluster default, or a specific name (e.g. local-path)
```

### 3.4 — Смонтируйте его в Deployment

Патчите `templates/deployment.yaml` — только новые части:

```yaml
volumeMounts:
  - name:                          # YOUR TASK: invent a volume name (match below)
    mountPath:                     # YOUR TASK: must equal DATA_DIR from Task 1
volumes:
  - name:                          # YOUR TASK: same name as the volumeMount above
    {{- if .Values.persistence.enabled }}
    persistentVolumeClaim:
      claimName:                   # YOUR TASK: same name as the PVC you authored above
    {{- else }}
    emptyDir: {}                   # fallback: data dies with the pod
    {{- end }}
```

### 3.5 — Доказательство персистентности (главное)

Это сердце лабораторной. **PVC `Bound` означает, что том существует, а НЕ что ваши данные пережили перезапуск pod'а.** Вы доказываете персистентность, записывая, удаляя pod и читая из нового pod'а.

`ВАША ЗАДАЧА`: сами разберитесь с четырьмя шагами. Вам понадобятся `kubectl exec ... -- sh -c 'echo ... > $DATA_DIR/marker'`, `kubectl delete pod`, `kubectl wait` и финальный `kubectl exec ... cat $DATA_DIR/marker`.

Используйте **отдельный файл** с именем `marker` для этого доказательства — не переиспользуйте `/data/visits`. Счётчик инкрементируется естественно, а вам нужна константная строка для сравнения. Оба файла живут на одном PVC, так что доказательство для `marker` — это также доказательство для `visits`.

```bash
# YOUR TASK: write a unique marker (e.g. epoch seconds) to $DATA_DIR/marker
#            inside the running pod (DATA_DIR defaults to /data — adjust if you changed it)
# YOUR TASK: delete the pod and wait for the Deployment to spin up a fresh one
# YOUR TASK: read $DATA_DIR/marker from the NEW pod
# YOUR TASK: prove the marker is the SAME — the write survived the pod's death
```

Результат сдачи — реальный зафиксированный вывод, показывающий *ту же* строку до и после. Если он отличается (или второй `cat` возвращает "No such file or directory"), ваш PVC на самом деле не смонтирован в каталог данных, или ваш класс хранилища делает что-то неожиданное — отладьте через `kubectl describe pvc` и `kubectl describe pod`.

> 💡 Вы можете увидеть `Unknown stream id 5` от `kubectl exec` — это безвредное клиентское предупреждение websocket, а не сбой. Если данные проходят туда-обратно, всё в порядке.

### 3.6 — Подтверждение работы

Вставьте в `docs/LAB12.md`:

- Изучение класса хранилища из 3.1 + ваши ответы
- Решение о режиме доступа из 3.2 с обоснованием
- `kubectl get pvc`, показывающий claim `Bound` (или `Pending`, если `WaitForFirstConsumer` и ни один pod ещё не потребил его — объясните, что именно)
- **Доказательство персистентности из 3.5: имя исходного pod'а, записанный marker, команда удаления, имя нового pod'а, чтение marker — то же значение, рядом**

---

## Задача 4 — Документация (2 балла)

Соберите всё в `docs/LAB12.md`. Обязательные разделы по порядку:

1. **Изменения приложения** — дизайн счётчика, `DATA_DIR`, обоснование атомарной записи, скриншот персистентности в Compose из задачи 1
2. **Дизайн ConfigMap** — ваш `files/config.json`, два ConfigMap, таблица решений из задачи 2.2, скриншоты проверки из 2.3
3. **Дизайн PVC** — изучение StorageClass, обоснование режима доступа, YAML PVC, монтирование, **главное доказательство персистентности из 3.5**
4. **ConfigMap vs Secret** — когда использовать каждый (область RBAC, tmpfs vs обычная ФС, история шифрования в состоянии покоя). Со ссылкой на лабораторную 11.
5. **Частые ловушки, в которые вы попали** — хотя бы одна реальная и как вы её отладили

---

## Бонусная задача — Горячая перезагрузка ConfigMap (2 балла)

Отредактируйте значение в `lab10-app-env`. Наблюдайте за работающим pod'ом. Переменная окружения **не меняется**. Отредактируйте значение в `lab10-app-file`. Наблюдайте за смонтированным файлом. Он **в конце концов** меняется — через минуты. А если бы вы использовали `subPath`, чтобы смонтировать его как отдельный файл? Он бы **никогда** не менялся.

Эти три поведения — причина, по которой каждая команда рано или поздно выбирает стратегию горячей перезагрузки. Ваша задача:

1. **Воспроизведите поведение по умолчанию.** `ВАША ЗАДАЧА`: отредактируйте значение через `kubectl edit configmap`, замерьте, сколько времени до (a) отражения изменения в переменной окружения внутри работающего pod'а — измеряйте в pod'е через `printenv` — и (b) отражения изменения в смонтированном файле — измеряйте через `cat` в цикле. Задокументируйте результат.

2. **Объясните `subPath`.** `ВАША ЗАДАЧА`: одним абзацем в `docs/LAB12.md` объясните, почему монтирование через `subPath` — это одноразовая копия, которая никогда не обновляется, и когда вы бы всё равно приняли этот компромисс (подсказка: чистые пути монтирования, без видимой приложению символьной ссылки `..data`).

3. **Выберите и реализуйте ОДНУ стратегию.** Не тянитесь к команде установки пока — изучите три варианта и выберите:

   - **A — аннотация с контрольной суммой (GitOps-нативно, без лишнего контроллера):** шаблон pod'а несёт аннотацию, значение которой — `sha256sum` отрендеренного ConfigMap. Любое изменение данных → изменение аннотации → Deployment раскатывается. Полностью реализуется в вашем шаблоне Helm.
   - **B — контроллер Reloader** (Stakater): контроллер в кластере наблюдает за ConfigMaps/Secrets и патчит владеющие Deployment для запуска раскатки. Ноль логики в чарте, одна аннотация.
   - **C — наблюдение на уровне приложения:** приложение `inotify`-наблюдает за смонтированным файлом и перечитывает его при изменении. Без перезапуска, мгновенно. Используется нативно NGINX, Envoy, Prometheus, Loki.

   `ВАША ЗАДАЧА`: в `docs/LAB12.md` напишите 3–4 предложения о том, какой вариант вы выбрали и **почему** (подумайте: подходит ли для GitOps? лишние движущиеся части? поддерживает ли ваше приложение вообще C?). Затем реализуйте его. **Команды установки или фрагменты аннотаций в этой лабораторной не показаны** — обратитесь к лекции, документации или README upstream и разберитесь.

4. **Продемонстрируйте, что работает.** `ВАША ЗАДАЧА`: измените значение ConfigMap, пронаблюдайте либо (a) раскатывающийся перезапуск для A/B, либо (b) перечитывание на месте для C. Зафиксируйте доказательства.

> 💡 Если вы выбрали A, хеш должен меняться при изменении **данных** ConfigMap. `helm upgrade` без изменений НЕ должен раскатывать pod. Если оба прогона `helm upgrade --dry-run` дают одну и ту же аннотацию, вы сделали всё правильно.

---

## Как сдавать

```bash
git switch -c lab12
git add app_python/ k8s/lab10-app/ docs/LAB12.md
git commit -m "feat(lab12): configmaps + persistence with hot-reload strategy"
git push -u origin lab12
```

Откройте **два** PR:

- `your-fork:lab12` → `course-repo:master` *(на проверку)*
- `your-fork:lab12` → `your-fork:master` *(сливается в ваш собственный main)*

Чек-лист PR:

```text
- [ ] Task 1 done — counter + /visits + DATA_DIR + atomic write + Compose persistence
- [ ] Task 2 done — two ConfigMaps, three patterns understood, decision table filled in
- [ ] Task 3 done — PVC bound, mounted, write→delete-pod→read proof captured
- [ ] Task 4 done — docs/LAB12.md complete with all five sections
- [ ] Bonus done — default behavior measured, strategy chosen + implemented + demonstrated
```

---

## Критерии приёмки

### Задача 1 (2 балла)
- ✅ `GET /` инкрементирует + сохраняет; `GET /visits` возвращает текущий счётчик
- ✅ Переменная окружения `DATA_DIR` учитывается; используется атомарная запись (временный + rename)
- ✅ Перезапуск в Compose сохраняет счётчик (зафиксировано)

### Задача 2 (3 балла)
- ✅ `files/config.json` + ConfigMap `lab10-app-file` (монтирование тома)
- ✅ ConfigMap `lab10-app-env` с ≥ 3 валидными ключами в форме env (`envFrom`)
- ✅ Таблица решений заполнена для каждого из трёх примеров значений, с обоснованием
- ✅ Скриншоты проверки: файл читается в pod'е, env-переменные присутствуют, `describe pod` показывает обвязку

### Задача 3 (3 балла)
- ✅ Изучение StorageClass задокументировано (какой, какой провайдер, какой `volumeBindingMode`)
- ✅ Режим доступа выбран + обоснован (`ReadWriteOnce` здесь корректен — обоснуйте его)
- ✅ PVC достигает `Bound` (или `Pending` объяснён через `WaitForFirstConsumer`)
- ✅ **Запись → удаление pod → чтение из нового pod, тот же marker, зафиксировано рядом**

### Задача 4 (2 балла)
- ✅ Все пять разделов в `docs/LAB12.md` завершены с реальными скриншотами (не иллюстративными)

### Бонус (2 балла)
- ✅ Поведение по умолчанию измерено: задержка обновления env-переменной + задержка обновления файла
- ✅ Ловушка `subPath` объяснена своими словами
- ✅ Одна стратегия (A/B/C) выбрана с письменным обоснованием, реализована, продемонстрирована

---

## Рубрика

| Задача | Баллы | Критерии |
|------|-------:|----------|
| **Задача 1** — Персистентность приложения | **2** | Счётчик + атомарная запись + доказательство в Compose |
| **Задача 2** — ConfigMaps | **3** | Два CM, понимание трёх паттернов, таблица решений |
| **Задача 3** — PVC | **3** | Правильный режим доступа, правильный размер/SC, главное доказательство персистентности |
| **Задача 4** — Документация | **2** | Все пять разделов LAB12.md с реальными доказательствами |
| **Бонус** — Горячая перезагрузка | **2** | Поведение по умолчанию измерено, стратегия выбрана + реализована + продемонстрирована |
| **Итого** | **12** | 10 основных + 2 бонусных |

**Руководство по оцениванию:**
- **10/10:** Все четыре задачи; доказательство персистентности недвусмысленно (тот же marker в обоих pod'ах); решения по ConfigMap обоснованы, а не просто выбраны
- **8–9/10:** ConfigMaps + PVC работают; доказательство персистентности присутствует, но рассуждения тонкие или одно решение по паттерну неверно
- **6–7/10:** PVC `Bound`, но нет доказательства запись→удаление→чтение, ИЛИ использован только один паттерн ConfigMap
- **< 6:** Нет доказательства персистентности, или ConfigMap не подключён к pod'у

---

## Ресурсы

<details>
<summary>📚 Документация</summary>

- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) — concepts
- [Configure a Pod with a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) — the three injection patterns
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) — PV/PVC/StorageClass
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) — `reclaimPolicy`, `volumeBindingMode`
- [Access Modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) — RWO/ROX/RWX/RWOP
- [Helm `.Files.Get`](https://helm.sh/docs/chart_template_guide/accessing_files/) — embed a file into a ConfigMap
- [local-path-provisioner](https://github.com/rancher/local-path-provisioner) — the default StorageClass in k3d

</details>

<details>
<summary>⚠️ Частые ловушки (из реальных прогонов — прочитайте ПЕРЕД отладкой)</summary>

- **Env-переменные ConfigMap не обновляются в работающем pod'е.** Измените `LOG_LEVEL` в CM, `printenv` в работающем pod'е по-прежнему показывает старое значение — навсегда, пока pod не перезапустится. Это причина №1 «моё обновление ConfigMap не работает». Env-переменные запекаются при старте pod'а; ничто это не меняет.
- **Монтирования `subPath` НИКОГДА не обновляются автоматически.** Монтирование `subPath: config.json` — это одноразовая копия файла при старте pod'а. ConfigMap может меняться каждые пять секунд; файл в контейнере — нет. Монтирования целого каталога обновляются автоматически (в пределах `kubelet --sync-frequency`, по умолчанию 60с + TTL кэша — общая задержка может быть пару минут). Если хотите горячую перезагрузку, монтируйте весь каталог.
- **PVC с `WaitForFirstConsumer` остаётся `Pending` — это норма, а не ошибка.** Класс хранилища по умолчанию на k3d (и на большинстве облачных SC в мульти-AZ кластерах) ждёт привязки, пока pod реально не смонтирует PVC, чтобы PV можно было провижинить в той же зоне, что и pod. Если ваш PVC в `Pending` и ни один pod ещё не потребил его, просто разверните pod — не пытайтесь «починить» SC.
- **`kubectl exec ... Unknown stream id` безвредно.** Клиентское сообщение websocket от безобидного несовпадения control-frame. Данные проходят туда-обратно нормально. Не гоняйтесь за ним.
- **Удаление PVC может НЕ удалить PV (или данные).** Зависит от `reclaimPolicy`: `Delete` (по умолчанию для облачных SC) стирает том; `Retain` сохраняет PV и диск после исчезновения PVC — вы должны чистить вручную. Ставьте `Retain` для всего, о потере чего вы бы плакали, и напишите runbook по очистке **до** дня, когда он понадобится.
- **Невалидные имена env-переменных из `envFrom` молча пропускаются.** Ключ ConfigMap `feature.x.enabled` не появится как env-переменная — `envFrom` выдаёт только ключи, соответствующие `[A-Z_][A-Z0-9_]*`. Без ошибки, без предупреждения, просто отсутствует.
- **`hostPath` для «настоящей» персистентности привязывает pod к узлу.** Только для демо. Используйте PVC даже для локальных кластеров — local-path провижинер даёт вам настоящий PVC, обеспеченный каталогом хоста, с правильной семантикой перепланирования.
- **Не перезаписывайте `/data/visits` своим marker.** Используйте *отдельный* файл (например, `/data/marker`) для доказательства персистентности из 3.5. Счётчик визитов переписывает `visits` при каждом `GET /`, что делает сравнение рядом ненадёжным.

</details>

<details>
<summary>🛠️ Полезный CLI (без YAML — только рецепты exec)</summary>

- `kubectl get sc` / `kubectl describe sc <name>` — какое хранилище предлагает кластер
- `kubectl describe pvc <name>` — смотрите Events внизу, когда PVC застрял
- `kubectl describe pod <name> | grep -A4 'Mounts\|Volumes'` — что реально смонтировано
- `kubectl exec <pod> -- mount | grep /data` — подтвердить, что том смонтирован
- `kubectl get events --field-selector involvedObject.name=<pvc>` — ошибки провижининга
- Для доказательства персистентности: запишите marker через `kubectl exec deploy/<name> -- sh -c 'echo $(date +%s) > /data/marker'` (НЕ `/data/visits` — счётчик его перезаписывает), затем `kubectl delete pod -l <selector>`, затем `kubectl wait --for=condition=Ready pod -l <selector> --timeout=60s`, затем `kubectl exec deploy/<name> -- cat /data/marker`

</details>

---

## Взгляд вперёд

| Лабораторная | Что добавляет |
|---:|---|
| 13 | ArgoCD GitOps — ваш ConfigMap + PVC согласуются из git |
| 14 | Argo Rollouts — canary нового ConfigMap до того, как его увидят все pod'ы |
| 15 | StatefulSets + `volumeClaimTemplates` — один PVC *на* реплику, для Postgres/Kafka |
| 16 | kube-prometheus-stack — сбор `/metrics` из вашего приложения, алерт на регрессии счётчика визитов |

> **Помните:** цель лабораторной — не «PVC `Bound`». Цель — «значение, которое я записал в pod A, вернулось из pod B после того, как я удалил pod A». Вот это — персистентность. Всё остальное — инфраструктура.
