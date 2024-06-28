resource "azurerm_resource_group" "bootstrap" {
  name     = var.name-resources
  location = var.location
}

resource "azurerm_user_assigned_identity" "cluster_id" {
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = var.location

  name = "${var.name}-cluster"
}

resource "azurerm_role_assignment" "node_group_role_assignment" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.cluster.node_resource_group}"
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.cluster_id.principal_id
}

resource "azurerm_role_assignment" "cluster_group_role_assignment" {
  scope                = azurerm_resource_group.bootstrap.id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.cluster_id.principal_id
}

resource "azurerm_virtual_network" "network" {
  name                = "${var.name}-network"
  location            = var.location
  resource_group_name = azurerm_resource_group.bootstrap.name
  address_space       = var.network.address_space
}

resource "azurerm_role_assignment" "sub_read_role_assignment" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.cluster_id.principal_id
}

resource "azurerm_route_table" "cluster" {
  name                = "${var.name}-route-table"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = var.location
}

resource "azurerm_subnet" "system_net" {
  name                 = "agent-nodepool"
  resource_group_name  = azurerm_resource_group.bootstrap.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.4.0/24"]
}

resource "azurerm_subnet" "agentnet" {
  name                 = "agent-nodepool02"
  resource_group_name  = azurerm_resource_group.bootstrap.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.8.0/24"]
}


resource "azurerm_subnet_route_table_association" "system-rt-asc" {
  subnet_id      = azurerm_subnet.system_net.id
  route_table_id = azurerm_route_table.cluster.id
}

resource "azurerm_subnet_route_table_association" "agent-rt-asc" {
  subnet_id      = azurerm_subnet.agentnet.id
  route_table_id = azurerm_route_table.cluster.id
}


resource "azurerm_kubernetes_cluster" "cluster" {
  kubernetes_version  = var.cluster.kubernetes_version
  name                = var.name
  location            = var.location
  resource_group_name = azurerm_resource_group.bootstrap.name
  dns_prefix          = "${var.name}-cluster"
  node_resource_group = "${var.name}-nodes"
  oidc_issuer_enabled = true

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.cluster_id.client_id
    object_id                 = azurerm_user_assigned_identity.cluster_id.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.cluster_id.id
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  default_node_pool {
    name                = "system"
    min_count           = 1
    max_count           = 5
    enable_auto_scaling = true
    vm_size             = "Standard_B2s"
    vnet_subnet_id      = azurerm_subnet.system_net.id
  }

  network_profile {
    network_plugin = "kubenet"

    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster_id.id]
  }

  depends_on = [
    azurerm_role_assignment.cluster_group_role_assignment,
    azurerm_subnet_route_table_association.system-rt-asc,
    azurerm_subnet_route_table_association.agent-rt-asc
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "agent" {
  name                  = "agents"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cluster.id
  vm_size               = "Standard_B2s"
  min_count             = 0
  max_count             = 1
  enable_auto_scaling   = true

  vnet_subnet_id = azurerm_subnet.agentnet.id
}

output "cluster_identity" {
  value = azurerm_user_assigned_identity.cluster_id.principal_id
}
