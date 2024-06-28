variable "cluster" {
  description = "Cluster Details"
  type = object({
    name               = string
    kubernetes_version = string
  })
}

variable "network" {
  description = "Values for Subnets, and network resources"
  type = object({
    address_space = list(any)
  })
}

variable "location" {
  description = "Location Of Azure Region."
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy resources to."
}

variable "subscription_id" {
  description = "Subscription to deploy resources to."
}

