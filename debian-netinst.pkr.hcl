packer {
  required_plugins {
    sshkey = {
      version = ">= 0.1.0"
      source = "github.com/ivoronin/sshkey"
    }
  }
}

data "sshkey" "install" {
}


variable "output_dir" {
  type    = string
  default = "output"
}

variable "output_name" {
  type    = string
  default = "debian.qcow2"
}

variable "source_checksum_url" {
  type    = string
  default = "file:https://cdimage.debian.org/cdimage/release/12.5.0/amd64/iso-cd/SHA256SUMS"
}

variable "source_iso" {
  type    = string
  default = "https://cdimage.debian.org/cdimage/release/12.5.0/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
}

variable "password" {
  type    = string
  default = "debian"
}

variable "username" {
  type    = string
  default = "debian"
}

build {
  description = <<EOF
This builder builds a QEMU image from a Debian "netinst" CD ISO file.
It contains a few basic tools and can be use as a "cloud image" alternative.
EOF

  sources = ["source.qemu.debian"]

  provisioner "file" {
    source      = "netinst/configure-qemu-image.sh"
    destination = "/tmp/configure-qemu-image.sh"
  }

  provisioner "shell" {
    inline = [
      "sh -cx 'sudo bash /tmp/configure-qemu-image.sh'"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y ansible"
    ]
  }

  provisioner "ansible-local" {
    playbook_file = "ansible/local-playbook.yml"
  }

  post-processor "manifest" {
    keep_input_artifact = true
  }
}

source qemu "debian" {
  iso_url      = "${var.source_iso}"
  iso_checksum = "${var.source_checksum_url}"

  cpus = 1
  memory      = 1000
  disk_size   = 8000
  accelerator = "kvm"

  headless = true

  http_port_min  = 9990
  http_port_max  = 9999
  http_content   = { "/preseed.cfg" = templatefile("netinst/preseed.cfg.pkrtpl", { "ssh_public_key" : data.sshkey.install.public_key, "username": var.username, "password": var.password }) }

  # SSH ports to redirect to the VM being built
  host_port_min             = 2222
  host_port_max             = 2229
  ssh_username              = "${var.username}"
  ssh_wait_timeout          = "1000s"
  ssh_private_key_file      = data.sshkey.install.private_key_path  
  ssh_clear_authorized_keys = true

  shutdown_command = "sudo -S /sbin/shutdown -hP now"

  # Builds a compact image
  disk_compression   = true
  disk_discard       = "unmap"
  skip_compaction    = false
  disk_detect_zeroes = "unmap"

  format           = "qcow2"
  output_directory = "${var.output_dir}"
  vm_name          = "${var.output_name}"

  boot_wait    = "1s"
  boot_command = [
    "<down><tab>", # non-graphical install
    "preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "language=en locale=en_US.UTF-8 ",
    "country=CH keymap=fr ",
    "hostname=packer domain=test ", # Should be overriden after DHCP, if available
    "<enter><wait>",
  ]
}
