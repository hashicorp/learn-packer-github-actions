packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
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
  ami_name    = "hashicups_{{timestamp}}"
  ami_regions = ["il-central-1"]
}

build {
  # HCP Packer settings
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


 # Copy SSH keys to the EC2 instance
  provisioner "file" {
    source      = "C:\\Users\\USER\\.ssh\\PACKER"
    destination = "/home/ec2-user/.ssh/id_ed25519"
  }
  provisioner "file" {
    source      = "C:\\Users\\USER\\.ssh\\PACKER.pub"
    destination = "/home/ec2-user/.ssh/id_ed25519.pub"
  }

  # Set appropriate permissions for the private key
  provisioner "shell" {
    inline = [
      "chmod 600 /home/ec2-user/.ssh/id_ed25519"
    ]
  }

  # systemd unit for HashiCups service
  provisioner "file" {
    source      = "hashicups.service"
    destination = "/tmp/hashicups.service"
  }

  # Set up HashiCups
  provisioner "shell" {
    scripts = [
      "setup-deps-hashicups.sh"
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