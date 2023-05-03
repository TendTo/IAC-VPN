# ===============================
# Terraform required variables
# ===============================
variable "iac_vpn_user_ocid" {
  type        = string
  description = "The OCID of the user"
}
variable "iac_vpn_tenancy_ocid" {
  type        = string
  description = "The OCID of the tenancy"
}
variable "iac_vpn_region" {
  type        = string
  description = "The region where the resources will be created"
}
variable "iac_vpn_fingerprint" {
  type        = string
  description = "The fingerprint of the public key"
}
variable "iac_vpn_oci_private_key_path" {
  type        = string
  description = "Path to the private key"
}
# ===============================
# Terraform optional variables
# ===============================
variable "iac_vpn_operating_system" {
  type        = string
  description = "The operating system to use for the instance. (Oracle Linux, Ubuntu, CentOS, ...)"
  default     = "Canonical Ubuntu"
}
variable "iac_vpn_operating_system_version" {
  type        = string
  description = "The version of the operating system to use for the instance. (8, 20.04, 8, ...)"
  default     = "22.04"
}
variable "iac_vpn_instance_shape" {
  type        = string
  description = "The shape of the instance. It determins the instance's computing power. (VM.Standard.A1.Flex, VM.Standard.E2.1.Micro, ...)"
  default     = "VM.Standard.E2.1.Micro"
}
variable "iac_vpn_instance_ocpus" {
  type        = number
  description = "The number of OCPUs to assign to the instance. Used if a flexible shape is chosen."
  default     = 1
}
variable "iac_vpn_instance_ram_gb" {
  type        = number
  description = "The amount of RAM in GB to assign to the instance. Used if a flexible shape is chosen."
  default     = 2
}
variable "iac_vpn_net_cidr" {
  type        = string
  description = "CIDR of the subnet. Meaning the range of IP addresses that will be available for the instances in the subnet."
  default     = "192.168.1.0/24"
}
variable "iac_vpn_subnet_cidr" {
  type        = string
  description = "CIDR of the subnet. Meaning the range of IP addresses that will be available for the instances in the subnet."
  default     = "192.168.1.0/25"
}
variable "iac_vpn_wireguard_port" {
  type        = number
  description = "Port to use for the wireguard server"
  default     = 51820
}
variable "iac_vpn_public_key" {
  type        = string
  description = "The public key to use for the instance. If not specified, a new key pair will be created."
  default     = ""
}

# ===============================
# Constants
# ===============================
locals {
  protocol_tcp   = "6"
  protocol_udp   = "17"
  protocol_icmp  = "1"
  protocol_all   = "all"
  protocl_icmpV6 = "58"
}

# Define required providers
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 4.118.0"
    }
  }
}

provider "oci" {
  region           = var.iac_vpn_region
  tenancy_ocid     = var.iac_vpn_tenancy_ocid
  user_ocid        = var.iac_vpn_user_ocid
  fingerprint      = var.iac_vpn_fingerprint
  private_key_path = var.iac_vpn_oci_private_key_path
}

# ===============================
# Availability Domain
# ===============================
data "oci_identity_availability_domain" "iac_vpc_ad" {
  compartment_id = var.iac_vpn_tenancy_ocid
  ad_number      = 1
}

# ===============================
# Available shapes
# ===============================
data "oci_core_images" "iac_vpn_images" {
  compartment_id           = oci_identity_compartment.iac_vpn_compartment.id
  operating_system         = var.iac_vpn_operating_system
  operating_system_version = var.iac_vpn_operating_system_version
  shape                    = var.iac_vpn_instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ===============================
# Compartment
# ===============================
resource "oci_identity_compartment" "iac_vpn_compartment" {
  compartment_id = var.iac_vpn_tenancy_ocid
  description    = "Compartment created by an IAC script to host a VPN"
  name           = "iac_vpn_compartment"
}

# ===============================
# Network
# ===============================
resource "oci_core_virtual_network" "iac_vpn_vcn" {
  compartment_id = oci_identity_compartment.iac_vpn_compartment.id
  cidr_block     = var.iac_vpn_net_cidr
}

resource "oci_core_subnet" "iac_vpn_subnet" {
  cidr_block        = var.iac_vpn_subnet_cidr
  security_list_ids = [oci_core_security_list.iac_vpn_security_list.id]
  compartment_id    = oci_identity_compartment.iac_vpn_compartment.id
  vcn_id            = oci_core_virtual_network.iac_vpn_vcn.id
  route_table_id    = oci_core_route_table.iac_vpn_route_table.id
  dhcp_options_id   = oci_core_virtual_network.iac_vpn_vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "iac_vpn_internet_gateway" {
  compartment_id = oci_identity_compartment.iac_vpn_compartment.id
  vcn_id         = oci_core_virtual_network.iac_vpn_vcn.id
}

resource "oci_core_route_table" "iac_vpn_route_table" {
  compartment_id = oci_identity_compartment.iac_vpn_compartment.id
  vcn_id         = oci_core_virtual_network.iac_vpn_vcn.id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.iac_vpn_internet_gateway.id
  }
}

resource "oci_core_security_list" "iac_vpn_security_list" {
  compartment_id = oci_identity_compartment.iac_vpn_compartment.id
  vcn_id         = oci_core_virtual_network.iac_vpn_vcn.id
  display_name   = "iac_vpn_security_list"

  egress_security_rules {
    protocol    = local.protocol_all
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = local.protocol_tcp
    source   = "0.0.0.0/0"

    tcp_options {
      max = 22
      min = 22
    }
  }

  ingress_security_rules {
    protocol = local.protocol_tcp
    source   = "0.0.0.0/0"

    tcp_options {
      max = 80
      min = 80
    }
  }

  ingress_security_rules {
    protocol = local.protocol_tcp
    source   = "0.0.0.0/0"

    tcp_options {
      max = var.iac_vpn_wireguard_port
      min = var.iac_vpn_wireguard_port
    }
  }

  ingress_security_rules {
    protocol = local.protocol_udp
    source   = "0.0.0.0/0"

    udp_options {
      max = var.iac_vpn_wireguard_port
      min = var.iac_vpn_wireguard_port
    }
  }
}

# ===============================
# Instance
# ===============================
resource "oci_core_instance" "iac_vpn_instance" {
  display_name        = "iac_vpn_instance"
  availability_domain = data.oci_identity_availability_domain.iac_vpc_ad.name
  compartment_id      = oci_identity_compartment.iac_vpn_compartment.id
  shape               = var.iac_vpn_instance_shape

  # If the shape supports customization of the number of OCPUs and amount of memory, provide values here
  # shape_config {
  #   ocpus         = var.iac_vpn_instance_ocpus
  #   memory_in_gbs = var.iac_vpn_instance_ram_gb
  # }

  create_vnic_details {
    subnet_id        = oci_core_subnet.iac_vpn_subnet.id
    display_name     = "iac_vpn_instance_vnic"
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.iac_vpn_images.images[0].id # Lookup?
  }

  metadata = {
    ssh_authorized_keys = var.iac_vpn_public_key != "" ? var.iac_vpn_public_key : one(tls_private_key.iac_vpn_ssh_key).public_key_openssh
  }
}

# ===============================
# SSH Key (if not provided)
# ===============================
resource "tls_private_key" "iac_vpn_ssh_key" {
  count     = var.iac_vpn_public_key != "" ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 2048
}

# ===============================
# Outputs
# ===============================
output "username" {
  value = "ubuntu"
}
output "private_key" {
  value     = var.iac_vpn_public_key != "" ? null : one(tls_private_key.iac_vpn_ssh_key).private_key_pem
  sensitive = true
}
output "public_ip" {
  value = oci_core_instance.iac_vpn_instance.public_ip
}
