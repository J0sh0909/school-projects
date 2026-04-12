> **[Francais](#francais)** | **[English](#english)**

## Français

> **Projet solo**

# AWS Vaultwarden - Déploiement Terraform

Déploiement Terraform en une seule commande d'un gestionnaire de mots de passe [Vaultwarden](https://github.com/dani-garcia/vaultwarden) auto-hébergé sur AWS. Provisionne toute la pile réseau, lance une instance EC2, installe Docker, exécute Vaultwarden derrière un proxy inverse Apache et obtient un certificat TLS Let's Encrypt - le tout depuis `terraform apply`.

> **Cours :** 420-H73-RO (AWS + Terraform)
> **Projet solo**

---

## Vue d'ensemble de l'architecture

<img width="800" height="612" alt="image" src="https://github.com/user-attachments/assets/8806260a-d1a9-436a-bbfc-a6e687f9ded4" />


**Ce que Terraform provisionne :**
- VPC (10.0.0.0/24) avec passerelle internet et table de routage publique
- Sous-réseau public avec une seule instance EC2 (t2.micro, Ubuntu 24.04)
- IP élastique attachée à l'instance
- Groupe de sécurité autorisant SSH, HTTP et HTTPS en entrée
- Paire de clés RSA 4096 générée à la volée pour le provisionnement SSH
- Script de démarrage téléchargé et exécuté via `remote-exec`

**Ce que le script de démarrage configure :**
- Installation de Docker CE et conteneur Vaultwarden (`vaultwarden/server:latest`) lié à `127.0.0.1:8080`
- Proxy inverse Apache faisant suivre `:443` vers `localhost:8080`
- Client No-IP DUC pour l'enregistrement DNS dynamique
- Certbot avec vérification DNS automatique - attend que le domaine résolve vers l'IP élastique avant de demander le certificat

---

## Fichiers

| Fichier | Rôle |
|---|---|
| `provider.tf` | Configuration du fournisseur AWS, contraintes de version Terraform, variables d'entrée |
| `main.tf` | Toutes les ressources d'infrastructure (VPC, sous-réseau, SG, EC2, EIP, provisionneur) |
| `script.sh` | Script de démarrage - installe Docker, Vaultwarden, Apache, Certbot, No-IP |

---

## Utilisation

```bash
# Définir les variables
export TF_VAR_noip_hostname="yourvault.ddns.net"
export TF_VAR_certbot_email="you@example.com"

# Déployer
terraform init
terraform apply
```

Après l'exécution, Vaultwarden est accessible à `https://<votre-hostname-noip>`.

> **Remarque :** Le fichier `provider.tf` utilise des valeurs de remplacement pour les identifiants AWS. Utilisez des variables d'environnement (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) ou un profil de credentials AWS plutôt que de les coder en dur.

---

## Fonctionnement

1. Terraform crée le VPC, le sous-réseau, la passerelle internet et la table de routage
2. Le groupe de sécurité ouvre les ports 22, 80 et 443
3. L'instance EC2 démarre avec une paire de clés SSH générée par Terraform
4. L'IP élastique est attachée à l'instance
5. `script.sh` est téléversé via SSH et exécuté en tant que root
6. Le script installe Docker, démarre Vaultwarden sur localhost:8080
7. Apache est configuré comme proxy inverse avec le domaine No-IP
8. No-IP DUC enregistre l'IP élastique auprès du nom d'hôte DNS dynamique
9. Le script interroge le DNS jusqu'à ce que le domaine résolve correctement, puis exécute Certbot pour émettre un certificat TLS

---

## Tech stack

Terraform, AWS (VPC, EC2, EIP, Security Groups), Docker, Vaultwarden, Apache, Let's Encrypt / Certbot, No-IP DUC

---

## English

> **Solo project**

# AWS Vaultwarden - Terraform Deployment

Single-command Terraform deployment of a self-hosted [Vaultwarden](https://github.com/dani-garcia/vaultwarden) password manager on AWS. Provisions the full networking stack, spins up an EC2 instance, installs Docker, runs Vaultwarden behind an Apache reverse proxy, and obtains a Let's Encrypt TLS certificate - all from `terraform apply`.

> **Course:** 420-H73-RO (AWS + Terraform)
> **Solo project**

---

## Architecture overview

<img width="800" height="612" alt="image" src="https://github.com/user-attachments/assets/8806260a-d1a9-436a-bbfc-a6e687f9ded4" />


**What Terraform provisions:**
- VPC (10.0.0.0/24) with internet gateway and public route table
- Public subnet with a single EC2 instance (t2.micro, Ubuntu 24.04)
- Elastic IP attached to the instance
- Security group allowing SSH, HTTP, and HTTPS inbound
- RSA 4096 key pair generated on the fly for SSH provisioning
- Bootstrap script uploaded and executed via `remote-exec`

**What the bootstrap script configures:**
- Docker CE installation and Vaultwarden container (`vaultwarden/server:latest`) bound to `127.0.0.1:8080`
- Apache reverse proxy forwarding `:443` to `localhost:8080`
- No-IP DUC client for dynamic DNS registration
- Certbot with automatic DNS verification - waits for the domain to resolve to the Elastic IP before requesting the certificate

---

## Files

| File | Purpose |
|---|---|
| `provider.tf` | AWS provider config, Terraform version constraints, input variables |
| `main.tf` | All infrastructure resources (VPC, subnet, SG, EC2, EIP, provisioner) |
| `script.sh` | Bootstrap script - installs Docker, Vaultwarden, Apache, Certbot, No-IP |

---

## Usage

```bash
# Set your variables
export TF_VAR_noip_hostname="yourvault.ddns.net"
export TF_VAR_certbot_email="you@example.com"

# Deploy
terraform init
terraform apply
```

After apply completes, Vaultwarden is live at `https://<your-noip-hostname>`.

> **Note:** The `provider.tf` uses placeholder values for AWS credentials. Use environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) or an AWS credentials profile instead of hardcoding them.

---

## How it works

1. Terraform creates the VPC, subnet, internet gateway, and route table
2. Security group opens ports 22, 80, and 443
3. EC2 instance launches with a Terraform-generated SSH key pair
4. Elastic IP is attached to the instance
5. `script.sh` is uploaded via SSH and executed as root
6. Script installs Docker, starts Vaultwarden on localhost:8080
7. Apache is configured as a reverse proxy with the No-IP domain
8. No-IP DUC registers the Elastic IP with the dynamic DNS hostname
9. Script polls DNS until the domain resolves correctly, then runs Certbot to issue a TLS certificate

---

## Tech stack

Terraform, AWS (VPC, EC2, EIP, Security Groups), Docker, Vaultwarden, Apache, Let's Encrypt / Certbot, No-IP DUC
