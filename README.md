# DHL IT Services - Confluent Kafka PaaS on AKS

The service provides a unified configuration of Confluent Kafka for multi-cloud deployment with various deployment options as K8s cluster of VM based cluster.

Solution components:

- **Multi-cloud portal** - PaaS Catalogue, Environment provisioning orchestration and automation, Input parameters, Approval workflows
- **Git** - source repository for automation scripts (AKS cluster creation, Confluent Kafka configuration etc.)
- **Azure Subscription** - for AKS based Confluent Kafka cluster and Azure Managed VMs cluster
- **VMware vSphere** - for on-premise VM based Confluent Kafka cluster
- **MS Teams Notification service** - environment provisioning progress notifications

Schema:

![alt text](https://github.com/krudisar/kafka-aks/blob/main/dhl-kafka.png)

**Demonstration video:**

Link: https://drive.google.com/file/d/1VKCbd2ETP3_7RxeHLhour-x4_LTbFKaa/view?usp=sharing
