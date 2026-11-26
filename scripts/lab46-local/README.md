# Локальная среда для лабораторных 4–6 (без облака, $0)

Каталог помогает пройти IaC (лаб. 4) и Ansible (лаб. 5–6) полностью локально.

## Вариант A — Ansible на хосте (по умолчанию, проще всего)

Ansible подключается к `localhost`, а Docker-контейнеры запускаются на хосте.
Это официально допустимый в курсе режим (`ansible_connection: local`).

```bash
cd scripts/lab46-local
ansible all -m ping                 # использует inventory.local.ini
ansible-playbook -i inventory.local.ini site.yml
```

Для задач, которым нужен `become`, на хосте должен быть доступен `sudo`.

## Вариант B — целевой контейнер с SSH и sudo

Ближе к «настоящему серверу»: Ubuntu 24.04 + sshd + пользователь `ansible` с
passwordless sudo. Без systemd (для лаб. 5–6 он не требуется).

```bash
cd scripts/lab46-local
./create-target.sh                  # соберёт и запустит lab46-target, порт 2222
ssh -i ./.ssh/lab46 -p 2222 ansible@127.0.0.1 'sudo whoami'   # => root
ansible -i inventory.ssh.ini web -m ping
ansible-playbook -i inventory.ssh.ini site.yml
```

Остановка/удаление:

```bash
docker rm -f lab46-target
```

> Если задачам нужен именно systemd (службы через `systemd`/`service`),
> поднимите локальную VM: `sudo snap install multipass && multipass launch 24.04 -n lab46`.
> Затем используйте её IP в `inventory.ssh.ini`. Это тоже локально и бесплатно.

## Лаб. 4 — Terraform/OpenTofu с Docker-провайдером

Реестры провайдеров (`registry.opentofu.org`, `registry.terraform.io`) в этом
окружении недоступны, поэтому провайдер ставится вручную из GitHub-релиза в
локальное filesystem-зеркало:

```bash
cd scripts/lab46-local/terraform-docker
bash fetch-provider.sh
export TF_CLI_CONFIG_FILE="$PWD/.terraformrc"
terraform init
terraform apply -auto-approve
curl -s localhost:8088 | head            # nginx отвечает (8080 занят на хосте)
terraform destroy -auto-approve
```

`terraform` здесь — shim на `tofu` (OpenTofu). Для Pulumi можно использовать тот
же Docker-провайдер, но сервер плагинов Pulumi (`get.pulumi.com`) в этом
окружении отдаёт 403, поэтому Pulumi-провайдеры придётся ставить вручную либо
использовать OpenTofu.
