resource "azurerm_resource_group" "bootsrap" {
  name     = var.name
  location = var.location
}

resource "azurerm_user_assigned_identity" "cluster_id" {
  resource_group_name = var.resource_group_name
  location            = var.location

  name = "${var.name}-cluster"
}

resource "azurerm_role_assignment" "node_group_role_assignment" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.cluster.node_resource_group}"
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.cluster_id.principal_id
}

resource "azurerm_role_assignment" "cluster_group_role_assignment" {
  scope                = azurerm_resource_group.bootsrap.id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.cluster_id.principal_id
}

resource "azurerm_virtual_network" "network" {
  name                = "${var.name}-network"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.network.address_space
}

resource "azurerm_role_assignment" "sub_read_role_assignment" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.cluster_id.principal_id
}

resource "azurerm_route_table" "cluster" {
  name                = "${var.name}-route-table"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_subnet" "agentnet" {
  name                 = "agent-nodepool"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.4.0/24"]
}

resource "azurerm_subnet" "agentnet2" {
  name                 = "agent-nodepool02"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.8.0/24"]
}


resource "azurerm_subnet_route_table_association" "agent-rt-asc" {
  subnet_id      = azurerm_subnet.agentnet.id
  route_table_id = azurerm_route_table.cluster.id
}

resource "azurerm_subnet_route_table_association" "agent-rt-asc2" {
  subnet_id      = azurerm_subnet.agentnet2.id
  route_table_id = azurerm_route_table.cluster.id
}


resource "azurerm_kubernetes_cluster" "cluster" {
  kubernetes_version  = var.cluster.kubernetes_version
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
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
    name                = "agent"
    min_count           = 1
    max_count           = 5
    enable_auto_scaling = true
    vm_size             = "Standard_B2s"
    vnet_subnet_id      = azurerm_subnet.agentnet.id
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
    azurerm_subnet_route_table_association.agent-rt-asc,
    azurerm_subnet_route_table_association.agent-rt-asc2
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "valheim" {
  name                  = "valheim"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cluster.id
  vm_size               = "Standard_D4s_v4"
  min_count             = 0
  max_count             = 1
  node_taints           = ["pool=valheim:NoSchedule"]
  node_labels           = { Pool = "valheim" }
  enable_auto_scaling   = true

  vnet_subnet_id = azurerm_subnet.agentnet.id

  tags = {
    Use = "Valheim Nodepool"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "agent2" {
  name                  = "btier"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.cluster.id
  vm_size               = "Standard_B2s"
  min_count             = 0
  max_count             = 1
  node_labels           = { subnet = "agent2" }
  enable_auto_scaling   = true

  vnet_subnet_id = azurerm_subnet.agentnet2.id
}

resource "azuread_application" "gb3s_app" {
  display_name = var.name
}

resource "azuread_application_federated_identity_credential" "example" {
  application_object_id = azuread_application.gb3s_app.object_id
  display_name          = "gb3s-runners"
  description           = "Deployments for my-repo"
  audiences             = ["api://AzureADTokenExchange"]
  issuer                = azurerm_kubernetes_cluster.cluster.oidc_issuer_url
  subject               = "system:serviceaccount:actions-runner-system:peon"
}

output "cluster_identity" {
  value = azurerm_user_assigned_identity.cluster_id.principal_id
}
