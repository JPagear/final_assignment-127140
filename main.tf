# main.tf

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0" 
    }
    local = {
      source = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# CORREÇÃO: Bloco locals movido para o nível raiz (resolve "Reserved block type name")
locals {
  # Variável local para o IP Público do Servidor (Jump Host)
  server_public_ip = azurerm_public_ip.publicip.ip_address
}


# --- 1. RECURSOS BÁSICOS ---

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "my-terraform-rg"
  location = var.location 
}

# Virtual Network and Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "my-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "my-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Network Security Group (to allow SSH and HTTP)
resource "azurerm_network_security_group" "nsg" {
  name                = "my-vm-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "ssh_rule" {
  name                        = "SSH_Access"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_network_security_group.nsg.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "http_rule" {
  name                        = "HTTP_Access"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_network_security_group.nsg.resource_group_name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_interface_security_group_association" "nic_nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}


# --- 2. SERVIDOR DHCP / NGINX (A VM principal) ---

# Public IP Address
resource "azurerm_public_ip" "publicip" {
  name                = "my-vm-publicip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "my-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }
}

# A Virtual Machine (Servidor Web e DHCP)
resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "my-ubuntu-vm"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = "Standard_B2S"
  network_interface_ids           = [azurerm_network_interface.nic.id]
  
  # SEGURANÇA: Autenticação por Chave SSH
  disable_password_authentication = true
  admin_username                  = "azureuser"
  
  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# --- 3. VM CLIENTE DE TESTE DHCP (Exercício 2 Validação) ---

# Network Interface para o Cliente (pega IP via DHCP)
resource "azurerm_network_interface" "client_nic" {
  name                = "my-client-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# VM Cliente de Teste
resource "azurerm_linux_virtual_machine" "client_vm" {
  name                            = "my-client-vm"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = "Standard_B1s"
  network_interface_ids           = [azurerm_network_interface.client_nic.id]
  
  disable_password_authentication = true
  admin_username                  = "azureuser"
  
  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_public_key
  }

  os_disk {
    caching              = "ReadOnly"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}


# --- 4. AUTOMAÇÃO ANSIBLE (EXERCÍCIO 1 & 2) ---

# Output do IP público do servidor (para teste Nginx)
output "public_ip_address" {
  value = azurerm_public_ip.publicip.ip_address
}

# Novo Output: IP Privado do Cliente (Verificação após DHCP renew)
output "client_private_ip" {
  value = azurerm_network_interface.client_nic.private_ip_address
}

# Criar Ficheiro de Inventário Dinâmico (inventory.ini)
resource "local_file" "inventory" {
  content  = <<-EOT
  [webservers]
  ${azurerm_public_ip.publicip.ip_address} ansible_user=azureuser ansible_ssh_private_key_file=${var.ssh_private_key_path}
  
  [dhcpservers]
  ${azurerm_public_ip.publicip.ip_address} ansible_user=azureuser ansible_ssh_private_key_file=${var.ssh_private_key_path}
  
  [clients]
  # O Ansible usará este IP para conectar e renovar o DHCP
  my-client-vm ansible_host=${azurerm_network_interface.client_nic.private_ip_address} ansible_user=azureuser ansible_ssh_private_key_file=${var.ssh_private_key_path}
  EOT
  filename = "${path.module}/inventory.ini"
}

# Executar Ansible: Configurar Nginx (Exercício 1)
resource "null_resource" "ansible_run_nginx" {
  depends_on = [azurerm_linux_virtual_machine.vm, local_file.inventory]

  provisioner "local-exec" {
    # Corrigindo ANSIIBLE_FORCE_COLOR para ANSIBLE_FORCE_COLOR
    command = "sleep 60 && ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_FORCE_COLOR=1 ansible-playbook -i ${local_file.inventory.filename} playbook.yml --private-key ${var.ssh_private_key_path}"
    working_dir = path.module
  }
}

# Executar Ansible: Configurar DHCP (Exercício 2)
resource "null_resource" "ansible_run_dhcp" {
  depends_on = [null_resource.ansible_run_nginx]

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_FORCE_COLOR=1 ansible-playbook -i ${local_file.inventory.filename} playbook-dhcp.yml --private-key ${var.ssh_private_key_path}"
    working_dir = path.module
  }
}

# FORÇAR RENOVAÇÃO DO IP NO CLIENTE (Validação DHCP)
resource "null_resource" "client_dhcp_renew" {
  # Deve depender da VM Cliente e do Servidor DHCP estarem prontos
  depends_on = [azurerm_linux_virtual_machine.client_vm, null_resource.ansible_run_dhcp]

  provisioner "local-exec" {
    # CORREÇÃO DE CONECTIVIDADE (Jump Host e Sleep)
    command = "sleep 15 && ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_FORCE_COLOR=1 ansible -i ${local_file.inventory.filename} clients -b -u azureuser -m shell -a 'dhclient -r ; dhclient' --private-key ${var.ssh_private_key_path} --ssh-extra-args='-o ProxyCommand=\"ssh -W %h:%p -q azureuser@${local.server_public_ip} -i ~/.ssh/id_rsa_azure\"'"
    working_dir = path.module
  }
}