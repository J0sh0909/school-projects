> **[Francais](#francais)** | **[English](#english)**

## Francais

> **Projet solo**

# Automatisation de tâches Asana

Script Python qui lit des fichiers XML structurés et crée toute la hiérarchie de projets Asana via l'API REST Asana - projets, sections, tâches et sous-tâches imbriquées jusqu'à 5 niveaux de profondeur.

> **Cours :** Scripting / Intégration API
> **Projet solo**

---

## Fonctionnement

Le schéma XML reflète la hiérarchie Asana : `PROJETS > PROJET > SECTIONS > SECTION > ACTIVITES > ACTIVITE`. Une `ACTIVITE` peut contenir des `ACTIVITES` imbriquées, permettant des chaînes de sous-tâches.

Le script traite un fichier en trois phases :

1. **Analyse et normalisation** - Lit le XML, met les balises et noms d'attributs en majuscules, capitalise les valeurs `NOM`, et demande les valeurs manquantes pour tout attribut à `?`
2. **Validation** - Parcourt le DOM selon le schéma, marque les nœuds invalides (balises inconnues, attributs requis manquants, noms en double, profondeur dépassée) pour les ignorer sans interrompre l'exécution
3. **Création** - S'authentifie avec un PAT, sélectionne l'espace de travail, puis crée chaque objet dans l'ordre. Les projets et sections sont vérifiés avant création pour éviter les doublons. Les tâches de premier niveau sont créées avec `memberships` pour les placer directement dans la bonne section. Les sous-tâches sont attachées via le point de terminaison de sous-tâches Asana de manière récursive.

Un indicateur `--dry-run` affiche l'arborescence résolue sans effectuer d'appels API.

---

## Structure XML

```xml
<PROJETS>
  <PROJET NOM="Project name" VUE="list" ACCES="prive">
    <SECTIONS>
      <SECTION NOM="Section name">
        <ACTIVITES>
          <ACTIVITE NOM="Task name" DESCRIPTION="Optional description">
            <ACTIVITES>
              <ACTIVITE NOM="Subtask" />
            </ACTIVITES>
          </ACTIVITE>
        </ACTIVITES>
      </SECTION>
    </SECTIONS>
  </PROJET>
</PROJETS>
```

---

## Utilisation

```bash
export ASANA_PAT="your-personal-access-token"
python creation_asana.py --f P01_Deploiements.xml
python creation_asana.py --f P01_Deploiements.xml --dry-run
```

---

## Fichiers

| Fichier | Objectif |
|---|---|
| `creation_asana.py` | Script principal - analyse XML, validation, création via l'API Asana |
| `P01_Deploiements.xml` | Exemple d'entrée - projet de déploiement avec sections et tâches |
| `Pratique.xml` | Exemple d'entrée - structure de projet de pratique |

---

## Tech stack

Python 3, Asana SDK (`asana`), `lxml`, `requests`, Asana REST API

---

## English

> **Solo project**

# Asana Task Automation

Python script that reads structured XML files and creates the full Asana project hierarchy via the Asana REST API - projects, sections, tasks, and nested subtasks up to 5 levels deep.

> **Course:** Scripting / API Integration
> **Solo project**

---

## How it works

The XML schema mirrors the Asana hierarchy: `PROJETS > PROJET > SECTIONS > SECTION > ACTIVITES > ACTIVITE`. An `ACTIVITE` can contain nested `ACTIVITES`, enabling subtask chains.

The script processes a file in three phases:

1. **Parse and normalize** - Reads the XML, uppercases all tags and attribute names, capitalises `NOM` values, and prompts for any attribute set to `?`
2. **Validate** - Walks the DOM against the schema, marking invalid nodes (unknown tags, missing required attributes, duplicate names, depth exceeded) to skip without halting
3. **Create** - Authenticates with a PAT, selects the workspace, then creates each object in order. Projects and sections are checked for existence before creation to avoid duplicates. Top-level tasks are created with `memberships` to place them directly into the correct section. Subtasks are attached via the Asana subtask endpoint recursively.

A `--dry-run` flag prints the resolved tree without making any API calls.

---

## XML structure

```xml
<PROJETS>
  <PROJET NOM="Project name" VUE="list" ACCES="prive">
    <SECTIONS>
      <SECTION NOM="Section name">
        <ACTIVITES>
          <ACTIVITE NOM="Task name" DESCRIPTION="Optional description">
            <ACTIVITES>
              <ACTIVITE NOM="Subtask" />
            </ACTIVITES>
          </ACTIVITE>
        </ACTIVITES>
      </SECTION>
    </SECTIONS>
  </PROJET>
</PROJETS>
```

---

## Usage

```bash
export ASANA_PAT="your-personal-access-token"
python creation_asana.py --f P01_Deploiements.xml
python creation_asana.py --f P01_Deploiements.xml --dry-run
```

---

## Files

| File | Purpose |
|---|---|
| `creation_asana.py` | Main script - XML parsing, validation, Asana API creation |
| `P01_Deploiements.xml` | Sample input - deployment project with sections and tasks |
| `Pratique.xml` | Sample input - practice project structure |

---

## Tech stack

Python 3, Asana SDK (`asana`), `lxml`, `requests`, Asana REST API
