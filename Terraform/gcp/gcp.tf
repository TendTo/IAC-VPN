# ===============================
# Terraform required variables
# ===============================
variable "iac_vpn_gcp_project" {
  type        = string
  description = "Project ID of the GCP project to use for the VPN"
}
variable "iac_vpn_region" {
  type        = string
  description = "GPC region where to deploy the VPN to (us-central1, us-east1, etc.)"
}
variable "iac_vpn_zone" {
  type        = string
  description = "GPC zone where to deploy the VPN to (us-central1-c, us-east1-b, etc.)"
}
# ===============================
# Terraform optional variables
# ===============================
variable "iac_vpn_machine_type" {
  type        = string
  description = "Machine type to use for the instance. It determins the instance's computing power. (e2-micro, e2-small, etc.)"
  default     = "e2-micro"
}
variable "iac_vpn_instance_image" {
  type        = string
  description = "Image to use for the instance. This is usually the ID of a snapshot (Ubuntu 20.04, CentOS 8, etc.)"
  default     = "debian-cloud/debian-11"
}
variable "iac_vpn_subnet_cidr" {
  type        = string
  description = "CIDR of the subnet to create. Meaning the range of IP addresses that will be available for the instances in the subnet."
  default     = "192.168.1.0/24"
}
variable "iac_vpn_wireguard_port" {
  type        = string
  description = "Port to use for the wireguard server"
  default     = "51820"
}


# Define required providers
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.63.1"
    }
  }
}

provider "google" {
  project = var.iac_vpn_gcp_project
  region  = var.iac_vpn_region
  zone    = var.iac_vpn_zone
}

# ===============================
# Key pair
# ===============================
data "google_client_openid_userinfo" "iac_vpc_user" {}

resource "tls_private_key" "iac_vpn_ssh_keys" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ===============================
# Network
# ===============================
resource "google_compute_network" "iac_vpn_network" {
  name                    = "iac-vpn-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "iac_vpc_subnet" {
  name          = "iac-vpn-subnet"
  ip_cidr_range = var.iac_vpn_subnet_cidr
  region        = var.iac_vpn_region
  network       = google_compute_network.iac_vpn_network.id
}

resource "google_compute_firewall" "iac_vpn_firewall" {
  name = "iac-vpn-firewall"
  allow {
    ports    = ["22"]
    protocol = "tcp"
  }
  allow {
    ports    = [var.iac_vpn_wireguard_port]
    protocol = "udp"
  }
  direction     = "INGRESS"
  network       = google_compute_network.iac_vpn_network.id
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
}

# ===============================
# Instance
# ===============================
resource "google_compute_instance" "iac_vpn_instance" {
  name         = "iac-vpn-instance"
  machine_type = var.iac_vpn_machine_type

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.iac_vpc_subnet.id
    access_config {
      # Include this section to give the VM an external ip address
    }
  }

  metadata = {
    ssh-keys = "${split("@", data.google_client_openid_userinfo.iac_vpc_user.email)[0]}:${tls_private_key.iac_vpn_ssh_keys.public_key_openssh}"
  }
}

# ===============================
# Output
# ===============================
output "username" {
  value = split("@", data.google_client_openid_userinfo.iac_vpc_user.email)[0]
}
output "private_key" {
  value     = tls_private_key.iac_vpn_ssh_keys.private_key_pem
  sensitive = true
}
output "public_ip" {
  value = google_compute_instance.iac_vpn_instance.network_interface.0.access_config.0.nat_ip
}
