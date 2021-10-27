terraform {
  required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = ">= 2.46"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "rg-leonardo-fs" {
  name     = "rg-leonardo-fs"
  location = "East US"
}

resource "azurerm_virtual_network" "vn-leonardo-fs" {
  name                = "vn-leonardo-fs"
  location            = azurerm_resource_group.rg-leonardo-fs.location
  resource_group_name = azurerm_resource_group.rg-leonardo-fs.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "VM"
  }
}

resource "azurerm_subnet" "sub-leonardo-fs" {
  name                 = "sub-leonardo-fs"
  resource_group_name  = azurerm_resource_group.rg-leonardo-fs.name
  virtual_network_name = azurerm_virtual_network.vn-leonardo-fs.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "ip-leonardo-fs" {
  name                = "ip-leonardo-fs"
  resource_group_name = azurerm_resource_group.rg-leonardo-fs.name
  location            = azurerm_resource_group.rg-leonardo-fs.location
  allocation_method   = "Static"

  tags = {
    environment = "IP Público"
  }
}

data "azurerm_public_ip" "data-ip-leonardo-fs" {
  resource_group_name = azurerm_resource_group.rg-leonardo-fs.name
  name = azurerm_public_ip.ip-leonardo-fs.name
}

resource "azurerm_network_security_group" "nsg-leonardo-fs" {
  name                = "nsg-leonardo-fs"
  location            = azurerm_resource_group.rg-leonardo-fs.location
  resource_group_name = azurerm_resource_group.rg-leonardo-fs.name

  security_rule {
    name                       = "mysql"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

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

  tags = {
    environment = "Network Sec. Group"
  }
}

resource "azurerm_network_interface" "ni-leonardo-fs" {
  name                = "ni-leonardo-fs"
  location            = azurerm_resource_group.rg-leonardo-fs.location
  resource_group_name = azurerm_resource_group.rg-leonardo-fs.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub-leonardo-fs.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-leonardo-fs.id
  }
  
  tags = {
    environment = "Interface de Rede"
  }
}

resource "azurerm_network_interface_security_group_association" "nisga-leonardo-fs" {
  network_interface_id      = azurerm_network_interface.ni-leonardo-fs.id
  network_security_group_id = azurerm_network_security_group.nsg-leonardo-fs.id
}

resource "azurerm_virtual_machine" "vm-leonardo-fs" {
  name                  = "vm-leonardo-fs"
  location              = azurerm_resource_group.rg-leonardo-fs.location
  resource_group_name   = azurerm_resource_group.rg-leonardo-fs.name
  network_interface_ids = [azurerm_network_interface.ni-leonardo-fs.id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "dsk-leonardo-fs"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "vm-leonardo-fs"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  tags = {
    environment = "VM Linux"
  }
}

output "publicip-vm-leonardo-fs" {
  value = azurerm_public_ip.ip-leonardo-fs.ip_address
}

resource "time_sleep" "esperar_30_segundos" {
  depends_on = [
    azurerm_virtual_machine.vm-leonardo-fs
  ]
  create_duration = "30s"
}

resource "null_resource" "deploy_db" {
  triggers = {
    order = null_resource.upload_db.id
  }
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "testadmin"
      password = "Password1234!"
      host = data.azurerm_public_ip.data-ip-leonardo-fs.ip_address
    }
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y mysql-server-5.7",
      "sudo mysql < /home/azureuser/config/user.sql",
      "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
      "sudo service mysql restart",
      "sleep 20",
    ]
  }
}