# school-projects - Josue Molina Ruelas

**Table des matières / Table of Contents**

- [Français](#français)
- [English](#english)

---

## Français

Portfolio de projets réalisés dans le cadre du programme **Virtualisation, sécurité et réseautique** au Cégep de Rosemont. Chaque dossier contient un README détaillé avec l'architecture, les choix techniques et ma contribution personnelle.

### Projets

| Projet | Description | Type |
|---|---|---|
| [aws-final-project](./cloud/aws-final-project/) | Infrastructure AWS multi-comptes avec VPC peering, VPN, RDS et surveillance CloudWatch | `Équipe (4)` |
| [aws-terraform-vaultwarden](./cloud/aws-terraform-vaultwarden/) | Déploiement Terraform d'un gestionnaire de mots de passe Vaultwarden sur AWS avec TLS automatique | `Solo` |
| [k3s-supervision](./monitoring/k3s-supervision/) | Cluster K3S Kubernetes avec pile de surveillance complète (Prometheus, Grafana, Loki) et pipeline CI/CD GitLab | `Équipe (3)` |
| [zabbix-supervision](./monitoring/zabbix-supervision/) | Déploiement Zabbix HA avec HAProxy, Keepalived et cluster MariaDB Galera | `Équipe (3)` |
| [docker-apache-mysql](./scripting/docker-apache-mysql/) | Déploiement Docker Compose d'Apache avec TLS auto-signé et MySQL | `Solo` |
| [paloalto-firewall](./network/paloalto-firewall/) | Deux labs Palo Alto : architecture DMZ avec NAT, puis déchiffrement SSL et intégration User-ID Active Directory | `Solo` |
| [2-tier-pki](./network/2-tier-pki/) | Infrastructure PKI Microsoft 2 niveaux avec AC racine hors ligne, AC subordonnée et IIS sécurisé par certificat | `Solo` |
| [ospf-routing](./network/ospf-routing/) | Réseau OSPF multi-zone avec 5 routeurs, 3 commutateurs et 8 VLANs sur deux sites | `Solo` |
| [enterprise-comms](./network/enterprise-comms/) | Infrastructure de communications d'entreprise sur Proxmox avec Zimbra, FreePBX (téléphones physiques) et Windows Server | `Équipe (2)` |
| [asana-task-automation](./scripting/asana-task-automation/) | Script Python créant des projets, sections, tâches et sous-tâches Asana depuis des fichiers XML via l'API REST | `Solo` |
| [cis-benchmark](./scripting/cis-benchmark/) | Scripts d'audit et de remédiation CIS pour Ubuntu 24.04 (Bash) et Windows 11 (PowerShell) | `Solo` |
| [user-management](./scripting/user-management/) | Scripts de création, désactivation et sauvegarde de comptes utilisateurs sur Linux et Windows (LDAP, AD, local) | `Solo` |

*La documentation des projets a été adaptée depuis les fichiers et travaux originaux de cours vers un format README avec l'aide de Claude par Anthropic.*

---

## English

Portfolio of projects completed in the **Virtualization, Security and Networking** program at Cégep de Rosemont. Each folder contains a detailed README with architecture, technical choices, and my personal contributions.

### Projects

| Project | Description | Type |
|---|---|---|
| [aws-final-project](./cloud/aws-final-project/) | Multi-account AWS infrastructure with VPC peering, VPN, RDS, and CloudWatch monitoring | `Team (4)` |
| [aws-terraform-vaultwarden](./cloud/aws-terraform-vaultwarden/) | Single-command Terraform deployment of a self-hosted Vaultwarden password manager on AWS with automatic TLS | `Solo` |
| [k3s-supervision](./monitoring/k3s-supervision/) | K3S Kubernetes cluster with a full monitoring stack (Prometheus, Grafana, Loki) and GitLab CI/CD pipeline | `Team (3)` |
| [zabbix-supervision](./monitoring/zabbix-supervision/) | HA Zabbix deployment with HAProxy, Keepalived VIP failover, and a 3-node MariaDB Galera cluster | `Team (3)` |
| [docker-apache-mysql](./scripting/docker-apache-mysql/) | Docker Compose deployment of Apache with self-signed TLS and a MySQL database backend | `Solo` |
| [paloalto-firewall](./network/paloalto-firewall/) | Two Palo Alto labs: DMZ architecture with NAT, then SSL decryption and Active Directory User-ID integration | `Solo` |
| [2-tier-pki](./network/2-tier-pki/) | 2-tier Microsoft PKI with an offline root CA, subordinate CA, and an IIS web server secured by the full certificate chain | `Solo` |
| [ospf-routing](./network/ospf-routing/) | Multi-area OSPF network with 5 routers, 3 switches, and 8 VLANs across two sites | `Solo` |
| [enterprise-comms](./network/enterprise-comms/) | Enterprise communications infrastructure on Proxmox with Zimbra, FreePBX (physical phones), and Windows Server | `Team (2)` |
| [asana-task-automation](./scripting/asana-task-automation/) | Python script that creates Asana projects, sections, tasks, and nested subtasks from structured XML files via the REST API | `Solo` |
| [cis-benchmark](./scripting/cis-benchmark/) | Audit and remediation scripts for CIS Benchmark compliance on Ubuntu 24.04 (Bash) and Windows 11 (PowerShell) | `Solo` |
| [user-management](./scripting/user-management/) | User account creation, deactivation, and backup scripts for Linux and Windows (LDAP, Active Directory, local) | `Solo` |

*Project documentation was adapted from original course materials and files into README format using Claude by Anthropic.*
