provider "azurerm" {}

locals {
  locale       = "japaneast"
  cluster_name = "openshift"
}

resource "azurerm_resource_group" "ocp" {
  name     = "${local.cluster_name}"
  location = "${local.locale}"

  tags {
    environment = "OpenShift All-in-One"
  }
}

resource "azurerm_virtual_network" "ocp" {
  name                = "ocpVnet"
  address_space       = ["10.0.0.0/16"]
  location            = "${local.locale}"
  resource_group_name = "${azurerm_resource_group.ocp.name}"

  tags {
    environment = "OpenShift All-in-One"
  }
}

resource "azurerm_public_ip" "ocp" {
  name                         = "ocpPublicIP"
  location                     = "${local.locale}"
  resource_group_name          = "${azurerm_resource_group.ocp.name}"
  public_ip_address_allocation = "dynamic"

  tags {
    environment = "OpenShift All-in-One"
  }
}

resource "azurerm_subnet" "ocp" {
  name                 = "mySubnet"
  resource_group_name  = "${azurerm_resource_group.ocp.name}"
  virtual_network_name = "${azurerm_virtual_network.ocp.name}"
  address_prefix       = "10.0.2.0/24"
}

resource "azurerm_network_security_group" "ocp" {
  name                = "ocpNetworkSecurityGroup"
  location            = "${local.locale}"
  resource_group_name = "${azurerm_resource_group.ocp.name}"

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "OcpMaster"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags {
    environment = "OpenShift All-in-One"
  }
}

resource "azurerm_network_interface" "ocp" {
  name                      = "ocpNIC"
  location                  = "${local.locale}"
  resource_group_name       = "${azurerm_resource_group.ocp.name}"
  network_security_group_id = "${azurerm_network_security_group.ocp.id}"

  ip_configuration {
    name                          = "ocpNicConfiguration"
    subnet_id                     = "${azurerm_subnet.ocp.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.ocp.id}"
  }

  tags {
    environment = "OpenShift All-in-One"
  }
}

resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = "${azurerm_resource_group.ocp.name}"
  }

  byte_length = 8
}

resource "azurerm_storage_account" "ocp" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = "${azurerm_resource_group.ocp.name}"
  location                 = "${local.locale}"
  account_replication_type = "LRS"
  account_tier             = "Standard"

  tags {
    environment = "OpenShift All-in-One"
  }
}

resource "azurerm_virtual_machine" "master" {
  name                  = "master"
  location              = "${local.locale}"
  resource_group_name   = "${azurerm_resource_group.ocp.name}"
  network_interface_ids = ["${azurerm_network_interface.ocp.id}"]
  vm_size               = "Standard_D4s_v3"

  storage_os_disk {
    name              = "myOsDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }

  storage_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "7-RAW"
    version   = "latest"
  }

  os_profile {
    computer_name  = "master"
    admin_username = "azureuser"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/azureuser/.ssh/authorized_keys"
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCuc0Gp/9hOu0YPN15ZqoIjqE/KG1zxncHWRzVvpk/B+tiVWz1Eq4F1k5dOwXxKw7ACsJfqxoJGT9GPmi41WiZkH70LdenMUIbiOuvj5ueaf21y6p6A7vybJkBSyT0qXp4sESeSgCQB3SWwexnXqe/zmTiM+6kBpTEQt/UDLazrMWW+H32Us82WPRDe176eEqqc/hi2FMfXHmZeTSVwmZTddaXPps6YEuZqPRc5HYjvbkX53hjb2XXLla4qmAQar5hUQ3MKJk+a7t4k0a/wfGbT76GrAnzYneU8Mu6DyKfyZwkP5X1bAlHYs3qOcuxPqOHNksbHW+4/FfbnWRPnMgN8rYS9StTfenWPmVyrEfdgqlm/lX4DttOQDRMQjChiCAibU5nd5lOU8ZcAYpao920uveirNKj/1NXsTLSX3zE5UiAD419dD13Zk6i0XEBvU8bE94YsIxYHgryvZA6gY1hrd7ZglKkL/9E25LMJDUi2OpzdjorHJL4cv+FkitlP4XP5Dw2uO1NoShm0156GPk3i2XU+kdpMN8AKqhn+g+QzZCJ8+ECgKGO0059FI2KmKP7CE6rsZfQoPtEL2SjPmEeOw7MPrq/zP/ezN0cBKxdXRkuyfIzhQm6v7E/wKkTJZkPOyp8PLoT4c9+1mDSnNOqpP20AXQKskVlJ8xiHyUJZYQ=="
    }
  }

  boot_diagnostics {
    enabled     = "true"
    storage_uri = "${azurerm_storage_account.ocp.primary_blob_endpoint}"
  }

  tags {
    environment = "OpenShift All-in-One"
  }
}
