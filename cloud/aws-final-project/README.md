> **[Francais](#francais)** | **[English](#english)**

## Français

> **Projet d'équipe (4 membres)** - voir le README pour les détails de contribution

# Infrastructure Cloud AWS

Infrastructure AWS multi-comptes déployant Mattermost, Nextcloud, GLPI et une base de données MySQL gérée, réparties sur deux VPC avec peering, accès SSH sécurisé par VPN, et surveillance CloudWatch avec alertes SNS.

> **Cours :** 420-H73-RO
> **Rôle :** Responsable du compte B (serveur GLPI, passerelle VPN, groupes de sécurité, peering VPC). A aussi configuré Mattermost dans le compte A et contribué à la mise en place du RDS.
> **Équipe :** 4 membres - projet final collaboratif

---

## Vue d'ensemble de l'architecture

<img width="800" height="706" alt="image" src="https://github.com/user-attachments/assets/2b1f301b-47e2-4e2b-a717-f2ac12efd0e8" />


**Compte A (us-east-1a)** héberge la couche applicative :

| Instance | Type | OS | Services | IP privée |
|---|---|---|---|---|
| Mattermost | t3.small | Ubuntu 24.04 | Apache (proxy inverse), Mattermost, GLPIInventory | 192.168.100.193 |
| Nextcloud | t3.micro | Ubuntu 24.04 | Apache, Nextcloud, GLPIInventory | 192.168.150.156 |
| RDS MySQL | db.t4g.micro | MySQL 8.0.43 | Base de données gérée pour Mattermost + Nextcloud | 192.168.50.156 |

**Compte B (us-east-1b)** héberge l'inventaire et l'accès VPN :

| Instance | Type | OS | Services | IP privée |
|---|---|---|---|---|
| GLPI | t3.small | Ubuntu 24.04 | Apache, GLPI, GLPIInventory | 192.168.0.11 |

---

## Services AWS utilisés

- **EC2** - Hébergement des applications (Mattermost, Nextcloud, GLPI)
- **RDS** - Base de données MySQL 8.0 gérée (sous-réseau privé, sans IP publique)
- **S3** - Stockage objet pour les fichiers utilisateurs Nextcloud
- **VPC + Peering** - Isolation réseau sur deux comptes avec connectivité inter-VPC
- **VPN** - Accès SSH sécurisé limité à 192.168.0.32/27
- **CloudWatch** - Tableaux de bord et alarmes basées sur des métriques par instance
- **SNS** - Notifications par email déclenchées par les alarmes CloudWatch
- **Route 53 / DNS** - Résolution de noms pour les points de terminaison HTTPS
- **Security Groups** - HTTPS ouvert à internet, SSH limité au sous-réseau VPN, RDS accessible uniquement depuis les sous-réseaux applicatifs

---

## Surveillance (CloudWatch)

Chaque instance EC2 et RDS dispose :
- D'un **tableau de bord** CloudWatch dédié pour suivre le CPU, la mémoire et les métriques réseau
- D'**alarmes** configurées pour les dépassements de seuils (pics CPU, mémoire faible)
- De **notifications email SNS** envoyées au déclenchement des alarmes

---

## Modèle de sécurité

- Tous les services web sont servis en **HTTPS** avec des certificats valides
- L'**accès SSH** est uniquement autorisé via le sous-réseau VPN (192.168.0.32/27) - pas d'SSH direct depuis internet
- **RDS n'a pas d'IP publique** - accessible uniquement depuis les instances applicatives au sein du VPC
- Les **groupes de sécurité** suivent le principe du moindre privilège : chaque instance a des règles entrée/sortie adaptées
- Les **agents GLPIInventory** fonctionnent sur toutes les instances EC2 et rapportent l'inventaire matériel et logiciel au serveur GLPI du compte B

---

## Ce que j'améliorerais

Dans un environnement de production :
- **RDS multi-AZ** pour le basculement de base de données
- **Elastic Load Balancer** devant Mattermost/Nextcloud pour la haute disponibilité
- **AWS Secrets Manager** pour la rotation des identifiants plutôt que des configs statiques
- **Politiques de cycle de vie S3** et versionnage pour la rétention des sauvegardes
- **Instantanés automatisés** exportés vers un compte AWS secondaire

---

## English

> **Team project (4 members)** - see README for contribution details

# AWS Cloud Infrastructure

Multi-account AWS infrastructure deploying Mattermost, Nextcloud, GLPI, and a managed MySQL database across two VPCs with peering, VPN-secured SSH access, and CloudWatch monitoring with SNS alerting.

> **Course:** 420-H73-RO
> **Role:** Owned Account B (GLPI server, VPN gateway, security groups, VPC peering). Also configured Mattermost in Account A and contributed to the RDS setup.
> **Team:** 4 members - collaborative final project

---

## Architecture overview

<img width="800" height="706" alt="image" src="https://github.com/user-attachments/assets/2b1f301b-47e2-4e2b-a717-f2ac12efd0e8" />


**Account A (us-east-1a)** hosts the application layer:

| Instance | Type | OS | Services | Private IP |
|---|---|---|---|---|
| Mattermost | t3.small | Ubuntu 24.04 | Apache (reverse proxy), Mattermost, GLPIInventory | 192.168.100.193 |
| Nextcloud | t3.micro | Ubuntu 24.04 | Apache, Nextcloud, GLPIInventory | 192.168.150.156 |
| RDS MySQL | db.t4g.micro | MySQL 8.0.43 | Managed database for Mattermost + Nextcloud | 192.168.50.156 |

**Account B (us-east-1b)** hosts inventory and VPN access:

| Instance | Type | OS | Services | Private IP |
|---|---|---|---|---|
| GLPI | t3.small | Ubuntu 24.04 | Apache, GLPI, GLPIInventory | 192.168.0.11 |

---

## AWS services used

- **EC2** - Application hosting (Mattermost, Nextcloud, GLPI)
- **RDS** - Managed MySQL 8.0 database (private subnet, no public IP)
- **S3** - Object storage for Nextcloud user files
- **VPC + Peering** - Network isolation across two accounts with cross-VPC connectivity
- **VPN** - Secure SSH access restricted to 192.168.0.32/27
- **CloudWatch** - Dashboards and metric-based alarms per instance
- **SNS** - Email alert notifications triggered by CloudWatch alarms
- **Route 53 / DNS** - Domain resolution for HTTPS endpoints
- **Security Groups** - HTTPS open to internet, SSH locked to VPN subnet, RDS accessible only from application subnets

---

## Monitoring (CloudWatch)

Each EC2 and RDS instance has:
- A dedicated CloudWatch **dashboard** tracking CPU, memory, and network metrics
- **Alarms** configured for threshold breaches (CPU spikes, low memory)
- **SNS email notifications** sent when alarms trigger

---

## Security model

- All web services are served over **HTTPS** with valid certificates
- **SSH access** is only permitted through the VPN subnet (192.168.0.32/27) - no direct SSH from the internet
- **RDS has no public IP** - only accessible from application instances within the VPC
- **Security groups** follow least-privilege: each instance has tailored inbound/outbound rules
- **GLPIInventory agents** run on all EC2 instances, reporting hardware and software inventory to the GLPI server in Account B

---

## What I'd improve

If this were a production environment:
- **Multi-AZ RDS** for database failover
- **Elastic Load Balancer** in front of Mattermost/Nextcloud for high availability
- **AWS Secrets Manager** for credential rotation instead of static configs
- **S3 lifecycle policies** and versioning for backup retention
- **Automated snapshots** exported to a secondary AWS account
