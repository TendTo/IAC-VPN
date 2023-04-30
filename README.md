# Infrastructure as Code (IAC) to setup a VPN

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/TendTo/IAC-VPN/releases/download/0.0.1/Oracle.zip)

Create your own VPN with a bunch of commands using this Infrastructure as Code (IAC) project.

## Requirements

- [Ansible](https://www.ansible.com/)
- [Wireguard](https://www.wireguard.com/)
- [Python](https://www.python.org/)
- [Terraform](https://www.terraform.io/) (if using a cloud provider)

## Run script

All operations have been made more convenient with a script.

Before running it, though, you may want to explore both the [Ansible configuration](#configuration) and the [Terraform configuration](#configuration-1) to see if you need to override some variables.

The script will usually be run two times: once to create the infrastructure, and once to setup the VPN using wireguard.

```shell
# Create the infrastructure
./run.sh oracle -y
```

```shell
# Setup the VPN (the become pass is the password of the sudo user on the local machine)
./run.sh wireguard -y -a --ask-become-pass
```

### Usage

```shell
Synopsis:
   ./run.sh [OPTIONS] <provider> [additional arguments]

Description:
    Handle all the steps to setup the infrastructure and initialize wireguard.

 Arguments:
    <provider>                    The provider to use. Valid options are: [openstack, oracle, wireguard].
                                  The last one will use Ansible to install and configure wireguard.
                                  Must be called after one of the other options.
    [additional arguments]        Additional arguments to pass to the provider

 Options:
    -h, --help                    Help section
    -d, --destroy                 When using a terraform provider, destroy the infrastructure
    -k, --key                     Name oo the private key to create or use (key.pem)
    -a, --ask-vault-pass          Ansible will ask for a password to decrypt the vault with
    -y, --yes                     Answer yes to all questions
    -n, --no-color                Disble color output
    -v, --version                 Script information
```

## Ansible

Ansible is used to setup the VPN on the computing instances.

### Configuration

The configuration is done in the `Ansible/inventory.yml` file.
There is an `inventory.yml.example` file that you can use as a template.  
If you use the `run.sh` script, some fields will be populated automatically, but others will need to be filled manually.

```yml
# File inventory.yml
all:
  hosts:
    vpn_server:
      ansible_host: 150.150.150.150 # server's public ip (populated automatically)
      ansible_user: ubuntu # server's user used for the ssh login
    vpn_client:
      ansible_host: localhost # client's ip. Should be leaved to localhost if you want to use the script locally
      ansible_connection: local # whether to setup the local machine as the vpn client
  vars:
    wireguard:
      internet: true # if true, the server will be configured to forward the traffic from the clients to the internet
      net: 10.0.0.0/24 # network used by the vpn
      server:
        sk: !vault | # private key of the server, encrypted with ansible vault
          $ANSIBLE_VAULT;1.1;AES256
          31393362353665373932373935373712613464373163366132353063666234373531616562313137
          ...
          6230363465383461383164336564376133326539333534376534
        pk: mpuKEyJXo/6WltxtIyC32ZVJaK275DBHuL25QbpWhUU=
        port: 51820 # port the vpn clients will connect to
        vpn_addr: "10.0.0.1" # address of the vpn server
        out_interface: ens3 # interface the server uses to connect to the internet
      client:
        sk: !vault | # private key of the client, encrypted with ansible vault
          $ANSIBLE_VAULT;1.1;AES256
          34323233326165123861323962333739653339656365326262356463383734376639363962646631
          ...
          303766303533613411303463643561356po29438633934356332
        pk: PIVPW3c/VGqHWodrwNKaEadCxFFp015Prtn+aS9mdzA= # public key of the client
        vpn_addr: "10.0.0.2" # address of the vpn client
```

The public keys and the private keys are used to authenticate the clients to the server inside the vpn.
They can both be generated with the `wg` command.

```shell
# Generate a private key
wg genkey > private_key
```

```shell
# Generate a public key from a private key
wg pubkey < private_key > public_key
```

To store the private keys in the `inventory.yml` file, you need to encrypt them with ansible vault.
You will be prompted to enter a password to encrypt the private key.  
Make sure to use the same password for both the server and the client private keys.

```shell
# Encrypt a private key
ansible-vault encrypt_string <private_key>
```

## Terraform

If you want to use a cloud provider, may use the terraform configurations in the `Terraform/<your provider>` directory.
For more information about each provider, check

- [Openstack](#openstack)
- [Oracle](#oracle)

### Configuration

Usually you will need to override some variables, or even some configurations.  
To do so, you can create a `terraform.tfvars` in the directory of the provider of your choice.
Otherwise, you will be prompted to enter the values for the required variables when running `terraform apply`.  
You can also provide different configurations with an `override.tf` file.

#### Example

```tf
# File terraform.tfvars
# Override the variable iac_vpn_external_network_id
iac_vpn_external_network_id = "my_external_network_id"
```

```tf
# File override.tf
# Override the configuration of the openstack provider
provider "openstack" {
  cloud = "my_cloud"
}
```

### Usage

First, you need to install the provider.
This can be done with

```shell
terraform init
```

Then, to create the infrastructure, run

```shell
terraform apply
```

Usually a ssh key pair is created together with the computing instances to allow you to connect to them via ssh.
Since the private key is sensitive information, it will not be shown by default.
To see it and store it in a file, run

```shell
terraform output -raw private_key > my_private_key.pem && chmod 600 my_private_key.pem
```

When you want to destroy the infrastructure, use

```shell
terraform destroy
```

## Terraform providers configuration

### Openstack

To configure the Openstack provider, you need to override the following variables in the `Terraform/openstack.` file:

- iac_vpn_external_network_id
- iac_vpn_image_id
- iac_vpn_flavor_name

Also, you need to configure the openstack provider:

```tf
# Configure the OpenStack Provider and choose the cloud to use
provider "openstack" {
  cloud = "" # Name of the cloud to use, usually set in ~/.config/openstack/clouds.yaml.
  # Alternatively, you can specify the credentials below.

  # user_name   = "admin"
  # tenant_name = "admin"
  # password    = "pwd"
  # auth_url    = "http://myauthurl:5000/v2.0"
  # region      = "RegionOne"
}
```

[Learn more about openstack configuration](https://docs.openstack.org/python-openstackclient/pike/configuration/index.html#configuration-files)

### Oracle

[Official guide](https://docs.oracle.com/en/learn/intro_terraform_linux)

To configure the Oracle provider, you need to override the following variables in the `Terraform/oracle.` file:

- iac_vpn_user_ocid
- iac_vpn_tenancy_ocid
- iac_vpn_region
- iac_vpn_fingerprint
- iac_vpn_oci_private_key_path

Most of these values should be found in the `~/.oci/config` file.
It should look like this:

```ini
[DEFAULT]
user=ocid1.user.oc1..aaaaaaaa...
fingerprint=aa:bb:cc:dd:ee:ff:gg:hh:ii:jj:kk:ll:mm:nn:oo:pp
key_file=~/.oci/oci_api_key.pem
tenancy=ocid1.tenancy.oc1..aaaaaaaa...
region=eu-frankfurt-1
```

If you don't have it, check [how to get keys and ocids](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm).

## Supported cloud providers and documentation

- [Openstack](https://www.openstack.org/)
  - [Terraform openstack provider](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs)
  - [Openstack Configuration](https://docs.openstack.org/python-openstackclient/pike/configuration/index.html#configuration-files)
- [Oracle](https://www.oracle.com/cloud/)
  - [Terraform oci provider](https://registry.terraform.io/providers/hashicorp/oci/latest)
  - [Official guide](https://docs.oracle.com/en/learn/intro_terraform_linux)
  - [How to get keys and ocids](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm)
