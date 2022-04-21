source "amazon-ebs" "ubuntu-hirsute" {
  region = "us-west-1"
  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name                = "ubuntu/images/*ubuntu-hirsute-21.04-amd64-server-*"
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"]
    most_recent = true
  }
  instance_type  = "t2.small"
  ssh_username   = "ubuntu"
  ssh_agent_auth = false

  ami_name    = "hashicups_{{timestamp}}"
  ami_regions = ["us-west-1"]
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
    "source.amazon-ebs.ubuntu-hirsute",
  ]

  ## HashiCups
  # Add startup script that will run hashicups on instance boot
  provisioner "file" {
    source      = "setup-deps-hashicups.sh"
    destination = "/tmp/setup-deps-hashicups.sh"
  }

  # Move temp files to actual destination
  # Must use this method because their destinations are protected 
  provisioner "shell" {
    inline = [
      "sudo cp /tmp/setup-deps-hashicups.sh /var/lib/cloud/scripts/per-boot/setup-deps-hashicups.sh",
    ]
  }

  post-processor "manifest" {
    output     = "packer_manifest.json"
    strip_path = true
    custom_data = {
      iteration_id = packer.iterationID
    }
  }
}
