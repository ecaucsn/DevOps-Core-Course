# Пример IaC для лаб. 4 без облака: Terraform/OpenTofu + Docker-провайдер.
# Реестр провайдеров недоступен, поэтому провайдер кладётся локально скриптом:
#   bash fetch-provider.sh
#   export TF_CLI_CONFIG_FILE="$PWD/.terraformrc"
#   terraform init && terraform apply
# (команда `terraform` — это shim на OpenTofu, см. INFRASTRUCTURE.md)
# Внешний порт 8088, т.к. 8080 на хосте уже занят.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0"
    }
  }
}

provider "docker" {}

resource "docker_image" "web" {
  name = "nginx:alpine"
}

resource "docker_container" "web" {
  name  = "lab4-web"
  image = docker_image.web.image_id

  ports {
    internal = 80
    external = 8088
  }

  labels {
    label = "course"
    value = "devops-core"
  }
}

output "url" {
  value = "http://localhost:8088"
}
