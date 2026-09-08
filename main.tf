terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # Targets the modern v4 Azure provider
    }
  }
}

provider "azurerm" {
  features {}
}

# 1. Create a Secure Resource Group (The container for all our parts)
resource "azurerm_resource_group" "rg" {
  name     = "rg-enterprise-java-prod"
  location = "East US"
}

# 2. Create an Isolated Virtual Network (VNet)
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-enterprise-prod"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# 3. Subnet A: Dedicated and Delegated strictly for PostgreSQL
resource "azurerm_subnet" "db_subnet" {
  name                 = "snet-postgres-private"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
  
  delegation {
    name = "fs"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# 4. Create the Secure Azure PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "postgres" {
  name                          = "pg-enterprise-java-db-${random_string.suffix.result}" # Unique name
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  version                       = "15"
  delegated_subnet_id           = azurerm_subnet.db_subnet.id
  public_network_access_enabled = false # Completely blocked from the internet!
  
  administrator_login    = "cloudadmin"
  administrator_password = "SecurePassword123!" # In real life, we pull this from Key Vault

  sku_name = "B_Standard_B1ms" # Cost-efficient tier
  zone     = "1"
}

# Helper to create a random string so your database name is unique on Azure
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# 5. Create a Service Plan for our Web App
resource "azurerm_service_plan" "plan" {
  name                = "asp-java-web-prod"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1" # Cost-efficient tier
}

# 6. Create the Linux Web App running Java 17
resource "azurerm_linux_web_app" "webapp" {
  name                = "app-enterprise-java-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.plan.id

  site_config {
    application_stack {
      java_version = "17"
      java_server  = "JAVA" # Running native Java SE jar container
    }
  }
}

# 7. The Service Connection (Links the Web App directly to Postgres)
resource "azurerm_web_app_connection" "connector" {
  name               = "conn-web-to-postgres"
  web_app_id         = azurerm_linux_web_app.webapp.id
  target_resource_id = azurerm_postgresql_flexible_server.postgres.id
  
  authentication {
    type = "secret"
  }
}
