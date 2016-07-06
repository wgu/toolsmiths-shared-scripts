############################################################################
# Notes: We currently need to manually create the storage table:
# `azure storage table create --account-name $storage_account_name --account-key $storage_account_key --table stemcell`
# https://github.com/hashicorp/terraform/issues/7257
#
############################## UPDATE BELOW #################################

# Follow instructions here to get credentials: https://www.terraform.io/docs/providers/azurerm/index.html
variable "azure_credentials" {
  default = {
    subscription_id = "your-subscription-id"
    client_id       = "your-client-id"
    client_secret   = "your-client-secret"
    tenant_id       = "your-tenant-id"
  }
}

variable "environment_name" {
  default = "your-environment-name"
}

variable "location" {
  default = "West US"
}

variable "address_space" {
  default = "10.0.0.0/16"
}

variable "subnets" {
  default = {
    bosh = "10.0.0.0/24"
    cloudfoundry =  "10.0.16.0/24"
    diego = "10.0.32.0/24"
  }
}

variable "devbox_configs" {
  default = {
    private_ip = "10.0.0.100"
    username = "your-devbox-admin-user"
    password = "your-devbox-admin-password"
    publickey = "public key string"
  }
}

######################################################################################

provider "azurerm" {
  subscription_id = "${var.azure_credentials.subscription_id}"
  client_id       = "${var.azure_credentials.client_id}"
  client_secret   = "${var.azure_credentials.client_secret}"
  tenant_id       = "${var.azure_credentials.tenant_id}"
}


resource "azurerm_resource_group" "resourcegroup" {
    name     = "${var.environment_name}"
    location = "${var.location}"
}

resource "azurerm_storage_account" "storageaccount" {
    name = "${var.environment_name}sa"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"

    location = "${var.location}"
    account_type = "Standard_LRS"
}

resource "azurerm_storage_container" "boshcontainer" {
    name = "bosh"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
    storage_account_name = "${azurerm_storage_account.storageaccount.name}"
    container_access_type = "private"
}

resource "azurerm_storage_container" "stemcellcontainer" {
    name = "stemcell"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
    storage_account_name = "${azurerm_storage_account.storageaccount.name}"
    container_access_type = "blob"
}

resource "azurerm_public_ip" "cloudfoundrypublicip" {
    name = "cloudfoundrypublicip"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
    public_ip_address_allocation = "static"
}

resource "azurerm_public_ip" "devboxpublicip" {
    name = "devboxpublicip"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
    public_ip_address_allocation = "static"
}

resource "azurerm_virtual_network" "virtualnetwork" {
  name                = "${var.environment_name}vnetwork"
  resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
  address_space       = ["${var.address_space}"]
  location            = "${var.location}"
}

resource "azurerm_subnet" "boshsubnet" {
    name = "boshnetwork"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
    virtual_network_name = "${azurerm_virtual_network.virtualnetwork.name}"
    address_prefix = "${var.subnets.bosh}"
}

resource "azurerm_subnet" "cloudfoundrysubnet" {
    name = "cloudfoundrynetwork"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
    virtual_network_name = "${azurerm_virtual_network.virtualnetwork.name}"
    address_prefix = "${var.subnets.cloudfoundry}"
}

resource "azurerm_subnet" "diegosubnet" {
    name = "diegonetwork"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
    virtual_network_name = "${azurerm_virtual_network.virtualnetwork.name}"
    address_prefix = "${var.subnets.diego}"
}

resource "azurerm_network_security_group" "boshsecuritygroup" {
    name = "boshsecuritygroup"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"

    security_rule {
        name = "ssh"
        priority = 200
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = 22
        source_address_prefix = "Internet"
        destination_address_prefix = "*"
    }

    security_rule {
        name = "bosh-agent"
        priority = 201
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = 6868
        source_address_prefix = "Internet"
        destination_address_prefix = "*"
    }

    security_rule {
        name = "bosh-director"
        priority = 202
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = 25555
        source_address_prefix = "Internet"
        destination_address_prefix = "*"
    }

    security_rule {
        name = "dns"
        priority = 203
        direction = "Inbound"
        access = "Allow"
        protocol = "*"
        source_port_range = "*"
        destination_port_range = 53
        source_address_prefix = "Internet"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_security_group" "cfsecuritygroup" {
    name = "cfsecuritygroup"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"

    security_rule {
        name = "cf-https"
        priority = 201
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = 443
        source_address_prefix = "Internet"
        destination_address_prefix = "*"
    }

    security_rule {
        name = "cf-log"
        priority = 202
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = 4443
        source_address_prefix = "Internet"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "devboxnic" {
    name = "devboxnic"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"

    ip_configuration {
        name = "devboxnic"
        subnet_id = "${azurerm_subnet.boshsubnet.id}"
        private_ip_address_allocation = "static"
        private_ip_address = "${var.devbox_configs.private_ip}"
        public_ip_address_id = "${azurerm_public_ip.devboxpublicip.id}"
    }
}

resource "azurerm_virtual_machine" "devboxvm" {
    name = "devboxvm"
    location = "${var.location}"
    resource_group_name = "${azurerm_resource_group.resourcegroup.name}"
    network_interface_ids = ["${azurerm_network_interface.devboxnic.id}"]
    vm_size = "Standard_D2_v2"

    storage_image_reference {
        publisher = "Canonical"
        offer = "UbuntuServer"
        sku = "14.04.3-LTS"
        version = "latest"
    }

    storage_os_disk {
        name = "devboxdisk"
        vhd_uri = "${azurerm_storage_account.storageaccount.primary_blob_endpoint}${azurerm_storage_container.boshcontainer.name}/devboxdisk.vhd"
        caching = "ReadWrite"
        create_option = "FromImage"
    }

    os_profile {
        computer_name = "${var.environment_name}jumpbox"
        admin_username = "${var.devbox_configs.username}"
        admin_password = "${var.devbox_configs.password}"
    }

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
          path = "/home/${var.devbox_configs.username}/.ssh/authorized_keys"
          key_data = "${var.devbox_configs.publickey}"
        }
    }
}

output "cloudfoundrypublicip" {
  value = "${azurerm_public_ip.cloudfoundrypublicip.ip_address}"
}

output "devboxpublicip" {
  value = "${azurerm_public_ip.devboxpublicip.ip_address}"
}

output "notes" {
  value = "We currently need to manually create the storage table:\nhttps://github.com/hashicorp/terraform/issues/7257\nhttps://github.com/hashicorp/terraform/issues/7257"
}

output "environment_variables" {
  value = <<EOF
Please export the following environments variables:

export VNET_NAME='${azurerm_virtual_network.virtualnetwork.name}'
export SUBNET_NAME='${azurerm_subnet.boshsubnet.name}'
export SUBSCRIPTION_ID='${var.azure_credentials.subscription_id}'
export CLIENT_ID='${var.azure_credentials.client_id}'
export CLIENT_SECRET='${var.azure_credentials.client_secret}'
export TENANT_ID='${var.azure_credentials.tenant_id}'
export RESOURCE_GROUP_NAME='${azurerm_resource_group.resourcegroup.name}'
export STORAGE_ACCOUNT_NAME='${azurerm_storage_account.storageaccount.name}'
export DEFAULT_SECURITY_GROUP='${azurerm_network_security_group.boshsecuritygroup.name}'
export BOSH_PUB_KEY='<REPLACE_WITH_YOUR_BOSH_PUB_KEY>'
export BOSH_PRIVATE_KEY_PATH='<REPLACE_WITH_YOUR_BOSH_PRIVATE_KEY_PATH>' # Path is relative to where your manifest will be on the dev box
EOF
}
