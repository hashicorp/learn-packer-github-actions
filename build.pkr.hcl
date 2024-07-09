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

source "amazon-ebs" "ubuntu-lts" {
  region = "il-central-1"
  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name                = "al2023-ami-2023.4.20240528.0-kernel-6.1-x86_64"
      root-device-type    = "ebs"
    }
    owners      = ["659248058490"]
    most_recent = true
  }
  instance_type  = "t3.micro"
  ssh_username   = "ec2-user"
  ssh_agent_auth = false
  ami_name       = "java-app-ami-{{timestamp}}"
  ami_regions    = ["il-central-1"]
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
    source      = var.COMPILED_JAR_PATH
    destination = "/tmp/artifacts/"
  }
  
  provisioner "shell" {
    script = "setup-java-app.sh"
  }
  
  post-processor "manifest" {
    output     = "packer_manifest.json"
    strip_path = true
    custom_data = {
      version_fingerprint = packer.versionFingerprint
    }
  }
}