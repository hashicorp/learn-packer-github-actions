packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "SSH_PACKER" {
  type = string
}

variable "SSH_PACKER_PUB" {
  type = string
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
  ami_name       = "hashicups_{{timestamp}}"
  ami_regions    = ["il-central-1"]
}

build {
  hcp_packer_registry {
    bucket_name = "learn-packer-github-actions"
    description = <<EOT
This is an image for HashiCups.
    EOT
    bucket_labels = {
      "hashicorp-learn" = "learn-packer-github-actions",
    }
  }
  
  sources = [
    "source.amazon-ebs.ubuntu-lts",
  ]
  
  provisioner "shell" {
    environment_vars = [
      "SSH_PACKER=${var.SSH_PACKER}",
      "SSH_PACKER_PUB=${var.SSH_PACKER_PUB}"
    ]
    inline = [
      "echo \"$SSH_PACKER\" > /tmp/id_ed25519",
      "echo \"$SSH_PACKER_PUB\" > /tmp/id_ed25519.pub",
      "chmod 600 /tmp/id_ed25519",
      "chmod 644 /tmp/id_ed25519.pub",
      "mkdir -p /home/ec2-user/.ssh",
      "mv /tmp/id_ed25519 /home/ec2-user/.ssh/",
      "mv /tmp/id_ed25519.pub /home/ec2-user/.ssh/",
      "chown ec2-user:ec2-user /home/ec2-user/.ssh/id_ed25519*"
    ]
  }
  
  provisioner "file" {
    source      = "hashicups.service"
    destination = "/tmp/hashicups.service"
  }
  
  provisioner "shell" {
    script = "setup-deps-hashicups.sh"
  }
  
  post-processor "manifest" {
    output     = "packer_manifest.json"
    strip_path = true
    custom_data = {
      version_fingerprint = packer.versionFingerprint
    }
  }
}