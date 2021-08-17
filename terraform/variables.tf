variable "agent_count" {
    default = 4 # -> a x node AKS cluster
}

variable "dns_prefix" {
    default = "aks-kafka"
}

variable cluster_name {
    default = "aks-kafka-cluster-2"
}

variable resource_group_name {
    default = "rg-krudisar-vmware-com"
}

variable location {
    default = "West Europe"
}

variable client_secret {
    default = ""
}

variable client_id {
     default = ""
}

