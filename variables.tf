variable "cluster" {
    description = "Cluster Details"
    type = object({
      name = string
      id = string
      location = string
      kubernetes_version = string
    })
}

variable "network" {
  description = "Values for Subnets, and network resources"
  type = object({
    id = string 
    name = string
    group = string
    group_id = string
    address_space = list()
  })
}

variable "subscription_id" {
}

