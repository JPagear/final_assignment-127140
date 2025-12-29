# variables.tf

# 1. Variável de Localização (Resolve o erro atual: "location = var.location")
variable "location" {
  type    = string
  default = "switzerlandnorth" # Usamos a região que você confirmou que funciona
}

# 2. Variável da Chave Pública (Injetada na VM para segurança)
variable "admin_public_key" {
  type        = string
  description = "SSH public key content for the admin user (must be provided via export)."
  sensitive   = false
}

# 3. Variável do Caminho da Chave Privada (Usada localmente pelo Ansible)
variable "ssh_private_key_path" {
  type        = string
  description = "Path to the private key used by Ansible."
  default     = "~/.ssh/id_rsa_azure"
}
