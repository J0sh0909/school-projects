> **[Francais](#francais)** | **[English](#english)**

## Français

> **Projet solo**

# Docker - Apache HTTPS auto-signé + MySQL

Déploiement Docker Compose d'un serveur web Apache avec certificats TLS auto-signés et un backend MySQL. Les deux services utilisent des volumes persistants pour que les données survivent aux redémarrages et reconstructions des conteneurs.

> **Cours :** Docker / Conteneurisation
> **Projet solo**

---

## Conteneurs

| Service | Image | Port exposé | Objectif |
|---|---|---|---|
| Serveur web | `apachephp-dhcp` (personnalisée) | 5000:443 | Apache + PHP avec TLS auto-signé |
| MySQL | `mysql:latest` | 3307:3306 | Backend de base de données |

Le conteneur web fonctionne avec des limites de ressources (0.25 CPU, 400 Mo RAM) et dépend du démarrage de la base de données.

### Volumes persistants

| Volume | Point de montage | Objectif |
|---|---|---|
| `web_data` | `/var/www/html` | Le contenu web persiste après les redémarrages |
| `mysql_data` | `/var/lib/mysql` | Les fichiers de base de données persistent après les redémarrages |

Un script d'initialisation `table.sql` est monté dans le répertoire d'entrée de MySQL pour amorcer la base de données au premier lancement.

---

## Fichiers

| Fichier | Objectif |
|---|---|
| `docker-compose.yml` | Définition de la pile complète - serveur web + MySQL + volumes + réseau |
| `Dockerfile` | Image Apache + PHP personnalisée avec TLS auto-signé et une page PHP interrogeant MySQL |
| `table.sql` | Script d'initialisation de la base de données - crée une table `noms` avec des données de test |
| `.env.example` | Modèle pour les variables d'environnement requises |

---

## Utilisation

```bash
# Copier et remplir les identifiants
cp .env.example .env

# Construire et démarrer
docker-compose up -d --build
```

L'application web est accessible à `https://localhost:5000` (avertissement de certificat auto-signé attendu).

---

## Fonctionnement

- Une image Docker personnalisée (`apachephp-dhcp`) sert le contenu en HTTPS sur le port 5000 avec un certificat auto-signé
- MySQL est initialisé avec une base de données et amorcé via `table.sql` au premier démarrage
- Les deux services partagent un réseau bridge (`app-network`) pour la communication interne
- Les volumes nommés garantissent la persistance des données après les redémarrages et reconstructions
- Un seul `docker-compose up -d` lance toute la pile

---

## Tech stack

Docker, Docker Compose, Apache (httpd), MySQL, OpenSSL (certificats auto-signés)

---

> *Remarque : Les identifiants ont été remplacés par des variables d'environnement pour des raisons de sécurité. Le déploiement original utilisait des valeurs codées en dur.*

---

## English

> **Solo project**

# Docker - Self-Signed HTTPS Apache + MySQL

Docker Compose deployment of an Apache web server with self-signed TLS certificates and a MySQL database backend. Both services use persistent volumes so data survives container restarts and rebuilds.

> **Course:** Docker / Containerization
> **Solo project**

---

## Containers

| Service | Image | Exposed Port | Purpose |
|---|---|---|---|
| Web server | `apachephp-dhcp` (custom) | 5000:443 | Apache + PHP with self-signed TLS |
| MySQL | `mysql:latest` | 3307:3306 | Database backend |

The web container runs with resource limits (0.25 CPU, 400MB RAM) and depends on the database being up first.

### Persistent volumes

| Volume | Mount Point | Purpose |
|---|---|---|
| `web_data` | `/var/www/html` | Web content persists across restarts |
| `mysql_data` | `/var/lib/mysql` | Database files persist across restarts |

A `table.sql` init script is mounted into MySQL's entrypoint directory to seed the database on first launch.

---

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Full stack definition - web server + MySQL + volumes + networking |
| `Dockerfile` | Custom Apache + PHP image with self-signed TLS and a PHP page querying MySQL |
| `table.sql` | Database seed script - creates a `noms` table with sample data |
| `.env.example` | Template for required environment variables |

---

## Usage

```bash
# Copy and fill in your credentials
cp .env.example .env

# Build and start
docker-compose up -d --build
```

The web app is available at `https://localhost:5000` (self-signed cert warning is expected).

---

## How it works

- A custom Docker image (`apachephp-dhcp`) serves content over HTTPS on port 5000 using a self-signed certificate
- MySQL is initialized with a database and seeded via `table.sql` on first boot
- Both services share a bridge network (`app-network`) for internal communication
- Named volumes ensure data survives container restarts and rebuilds
- A single `docker-compose up -d` brings up the full stack

---

## Tech stack

Docker, Docker Compose, Apache (httpd), MySQL, OpenSSL (self-signed certs)

---

> *Note: Credentials have been replaced with environment variables for security. The original deployment used hardcoded values.*
