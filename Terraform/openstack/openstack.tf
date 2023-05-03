# ===============================
# Terraform required variables
# ===============================
variable "iac_vpn_external_network_id" {
  type        = string
  description = "ID of the external network to connect to, used to access the internet"
}
variable "iac_vpn_instance_image_id" {
  type        = string
  description = "ID of the image to use for the instance. This is usually the ID of a snapshot (Ubuntu 20.04, CentOS 8, etc.)"
}
variable "iac_vpn_instance_flavor_name" {
  type        = string
  description = "Name of the flavor to use for the instance. It determins the instance's computing power. (m1.small, m1.medium, etc.)"
}
# ===============================
# Terraform optional variables
# ===============================
variable "iac_vpn_cloud" {
  type = string
  description = "Cloud authentication credentials to use. It should be specified in ~/.config/openstack/clouds.yaml"
  default = ""
}
variable "iac_vpn_subnet_cidr" {
  type        = string
  description = "CIDR of the subnet to create. Meaning the range of IP addresses that will be available for the instances in the subnet."
  default     = "192.168.1.0/24"
}
variable "iac_vpn_wireguard_port" {
  type        = number
  description = "Port to use for the wireguard server"
  default     = 51820
}

# Define required providers
terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.48.0"
    }
  }
}

# Configure the OpenStack Provider and choose the cloud to use
provider "openstack" {
  cloud = var.iac_vpn_cloud # Name of the cloud to use, usually set in ~/.config/openstack/clouds.yaml.
  # Alternatively, you can specify the credentials below.

  # user_name   = "admin"
  # tenant_name = "admin"
  # password    = "pwd"
  # auth_url    = "http://myauthurl:5000/v2.0"
  # region      = "RegionOne"
}

# ===============================
# Key pair
# ===============================
resource "openstack_compute_keypair_v2" "iac_vpn_keypair" {
  name = "iac_vpn_keypair"
}

# ===============================
# Network
# ===============================
resource "openstack_networking_floatingip_v2" "iac_vpn_public_ip" {
  pool        = "floating-ip"
  description = "Public IP used to access the VPN server"
}

resource "openstack_compute_floatingip_associate_v2" "iac_vpn_public_ip_association" {
  floating_ip = openstack_networking_floatingip_v2.iac_vpn_public_ip.address
  instance_id = openstack_compute_instance_v2.iac_vpn_instance.id
  fixed_ip    = openstack_compute_instance_v2.iac_vpn_instance.network.0.fixed_ip_v4
}

resource "openstack_networking_network_v2" "iac_vpn_network" {
  name           = "iac_vpn_network"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "iac_vpn_subnet" {
  name            = "iac_vpn_subnet"
  network_id      = openstack_networking_network_v2.iac_vpn_network.id
  cidr            = var.iac_vpn_subnet_cidr
  ip_version      = 4
  dns_nameservers = ["8.8.8.8"]
}

resource "openstack_networking_router_v2" "iac_vpn_router" {
  external_network_id = var.iac_vpn_external_network_id
}

resource "openstack_networking_router_interface_v2" "iac_vpn_router_interface" {
  router_id = openstack_networking_router_v2.iac_vpn_router.id
  subnet_id = openstack_networking_subnet_v2.iac_vpn_subnet.id
}

resource "openstack_compute_secgroup_v2" "iac_vpn_secgroup" {
  name        = "iac_vpn_secgroup"
  description = "Security group for instances that need to be accessed from the wireguard port"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = var.iac_vpn_wireguard_port
    to_port     = var.iac_vpn_wireguard_port
    ip_protocol = "udp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = var.iac_vpn_wireguard_port
    to_port     = var.iac_vpn_wireguard_port
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
}

# ===============================
# Instance
# ===============================
resource "openstack_compute_instance_v2" "iac_vpn_instance" {
  name            = "iac_vpn_instance"
  image_id        = var.iac_vpn_instance_image_id
  flavor_name     = var.iac_vpn_instance_flavor_name
  key_pair        = openstack_compute_keypair_v2.iac_vpn_keypair.name
  security_groups = [openstack_compute_secgroup_v2.iac_vpn_secgroup.name]

  metadata = {
    application = "iac_vpn"
  }

  network {
    uuid = openstack_networking_network_v2.iac_vpn_network.id
  }
}

# ===============================
# Outputs
# ===============================
output "username" {
  value = "ubuntu"
}
output "private_key" {
  value     = openstack_compute_keypair_v2.iac_vpn_keypair.private_key
  sensitive = true
}
output "public_ip" {
  value = openstack_networking_floatingip_v2.iac_vpn_public_ip
}
