packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "SSH_PACKER" {
  type        = string
  description = "תוכן מפתח SSH פרטי"
  default     = ""
}

variable "SSH_PACKER_PUB" {
  type        = string
  description = "תוכן מפתח SSH ציבורי"
  default     = ""
}

variable "COMPILED_JAR_PATH" {
  type        = string
  description = "נתיב לקובץ ה-JAR המקומפל מ-GitHub Actions"
}

variable "source_ami" {
  type        = string
  description = "AMI ID to use as a base"
}

source "amazon-ebs" "ubuntu-lts" {
  region          = "il-central-1"
  source_ami      = var.source_ami
  instance_type   = "t3.micro"
  ssh_username    = "ec2-user"
  ssh_agent_auth  = false
  ami_name        = "java-app-ami-{{timestamp}}"
  ami_regions     = ["il-central-1"]
}

build {
  hcp_packer_registry {
    bucket_name = "learn-packer-github-actions"
    description = <<EOT
זוהי תמונה עבור אפליקציית Java.
    EOT
    bucket_labels = {
      "hashicorp-learn" = "learn-packer-github-actions",
    }
  }

  sources = [
    "source.amazon-ebs.ubuntu-lts",
  ]

  provisioner "file" {
  source      = "${var.COMPILED_JAR_PATH}"
  destination = "/tmp/artifacts/"
}

provisioner "shell" {
  inline = [
    "ls -l /tmp/artifacts/",
    "echo 'Contents of /tmp/artifacts:'",
    "find /tmp/artifacts -type f -name '*.jar'"
  ]
}

provisioner "shell" {
  script = "setup-deps-hashicups.sh"
}

  provisioner "shell" {
  inline = [
    "echo 'Contents of /opt/myapp after setup:'",
      "ls -l /opt/myapp/",
      "echo 'Checking if myapp service is enabled:'",
      "systemctl is-enabled myapp.service",
      "echo 'Checking if launch script exists:'",
      "ls -l /opt/instance_launch.sh",
      "echo 'Checking if launch script is added to rc.local:'",
      "grep '/opt/instance_launch.sh' /etc/rc.local"
  ]
}

  post-processor "manifest" {
    output     = "packer_manifest.json"
    strip_path = true
    custom_data = {
      version_fingerprint = packer.versionFingerprint
    }
  }
}