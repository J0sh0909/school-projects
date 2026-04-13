#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# ======================================================================
#  Asana XML → Projets / Sections / Activités
#  Objectif :
#  - Lire un XML structuré (PROJET/SECTION/ACTIVITE)
#  - Valider la structure et les attributs
#  - Créer les objets Asana (projet, sections, tâches, sous-tâches)
#  - Placer les tâches top-level directement dans la bonne section (memberships)
#  - Offrir un mode --dry-run pour inspecter sans écrire dans Asana
#  - Journaliser en français avec des f-strings
# ======================================================================

# Final remarks: I got a 92.5% for this exam, the only issue I had was that I misconfigured the type of view for the asana project (shoulda been able to turn from private to public or vice versa based on xml structure specifications)

import os
import sys
import argparse
from lxml import etree
import requests
import asana
from asana.rest import ApiException

# Typologie des erreurs pour homogénéiser les messages.
types_erreurs = [
    "AVERTISSEMENT",
    "ERREUR NON FATALE",
    "ERREUR FATALE",
]

# Catalogue des erreurs, indexées et utilisées telles quelles.
erreurs = [
    # 0-6  : fichiers / parsing
    f"{types_erreurs[2]}: aucun paramètre (fichier) fourni. Utilisez --help pour voir les options valides.",  # 0
    (  # 1: aide/args
        f"{types_erreurs[1]}: --f nécessite au moins un fichier.",                   # 1[0]
        f"{types_erreurs[1]}: --p nécessite exactement un paramètre.",               # 1[1]
        f"{types_erreurs[1]}: --w nécessite exactement un paramètre.",               # 1[2]
        f"{types_erreurs[1]}: --help ne prend aucun argument.",                      # 1[3]
    ),
    f"{types_erreurs[1]}: fichier introuvable '{{fichier}}'.",                      # 2
    f"{types_erreurs[0]}: impossible de lire '{{fichier}}' en UTF-8: {{error}}",    # 3
    f"{types_erreurs[0]}: le fichier '{{fichier}}' n’a pas l’extension .xml",       # 4
    f"{types_erreurs[1]}: syntaxe XML incorrecte",                                  # 5
    f"{types_erreurs[1]}: erreur inattendue lors de l'ouverture/analyse de '{{fichier}}': {{error}}",  # 6

    # 7-13 : schéma / validation
    f"{types_erreurs[1]}: attribut(s) manquant(s) {{attrs}} dans {{tag}}",           # 7
    f"{types_erreurs[1]}: type de nœud non pris en charge '{{node}}' (ignoré avec ses descendants)",  # 8
    f"{types_erreurs[1]}: pseudo-nœud dupliqué {{attrs}} dans {{tag}} (nœud ignoré)",                 # 9
    f"{types_erreurs[1]}: attribut inconnu '{{attr}}' dans {{tag}} (ignoré)",       # 10
    f"{types_erreurs[1]}: doublon attribut/pseudo-nœud '{{cle}}' dans {{tag}} (nœud ignoré avec descendants)", # 11
    f"{types_erreurs[1]}: racine invalide: doit être PROJETS ou PROJET",            # 12
    f"{types_erreurs[1]}: profondeur maximale de sous-activités dépassée ({{max}}). Nœud ignoré",     # 13

    # 14-18 : authentification / utilisateur / workspace
    f"{types_erreurs[2]}: aucun jeton d'accès (PAT) fourni.",                        # 14
    f"{types_erreurs[2]}: erreur inattendue lors de la récupération de l'utilisateur: {{error}}",     # 15
    f"{types_erreurs[2]}: utilisateur introuvable ou données incomplètes.",         # 16
    f"{types_erreurs[2]}: aucun espace de travail trouvé pour l'utilisateur {{utilisateur}}.",        # 17
    f"{types_erreurs[1]}: sélection d'espace de travail invalide.",                 # 18

    # 19-25 : erreurs HTTP Asana
    f"{types_erreurs[1]} (HTTP 400): requête Asana invalide.",                      # 19
    f"{types_erreurs[2]} (HTTP 401): jeton PAT invalide ou expiré.",                # 20
    f"{types_erreurs[2]} (HTTP 403): accès refusé à la ressource Asana.",           # 21
    f"{types_erreurs[1]} (HTTP 404): ressource Asana introuvable.",                 # 22
    f"{types_erreurs[0]} (HTTP 409): ressource déjà existante.",                    # 23
    f"{types_erreurs[2]} (HTTP 429): limite de requêtes Asana atteinte.",           # 24
    f"{types_erreurs[2]} (HTTP 500–503): erreur interne du serveur Asana.",         # 25
]


# Paramètres de lecture et de validation du XML.
VUE_DEFAUT = "list"
ACCES_DEFAUT = "privé"
SOUS_TACHE_PROFONDEUR_MAX = 5

PLURIEL = {"PROJETS", "SECTIONS", "ACTIVITES"}
SCHEMA = {
    "PROJETS":   {"children": ["PROJET"],    "attrs": {"required": [],        "optional": []}},
    "PROJET":    {"children": ["SECTIONS"],  "attrs": {"required": ["NOM"],   "optional": ["VERSION", "DESCRIPTION", "ACCÈS", "VUE"]}},
    "SECTIONS":  {"children": ["SECTION"],   "attrs": {"required": [],        "optional": []}},
    "SECTION":   {"children": ["ACTIVITES"], "attrs": {"required": ["NOM"],   "optional": []}},
    "ACTIVITES": {"children": ["ACTIVITE"],  "attrs": {"required": [],        "optional": []}},
    "ACTIVITE":  {"children": ["ACTIVITES"], "attrs": {"required": ["NOM"],   "optional": ["DESCRIPTION"]}},
}

# ----------------------------------------------------------------------
# Utilitaires XML
# ----------------------------------------------------------------------
def _cap_phrase(texte: str) -> str:
    """
    Capitalise la première lettre d’une chaîne non vide.
    """
    s = (texte or "").strip()
    return s[0].upper() + s[1:] if s else s

def uniformiser(noeud):
    """
    Normalise le DOM :
    - Tags en majuscules
    - Noms d’attributs en majuscules
    - Capitalisation de la valeur 'NOM'
    - Interrogation utilisateur si <NOM> contient '?'
    """
    if hasattr(noeud, "tag") and isinstance(noeud.tag, str):
        noeud.tag = noeud.tag.strip().upper()

    if getattr(noeud, "attrib", None):
        for k, v in list(noeud.attrib.items()):
            cle = k.strip().upper()
            val = (v or "").strip()
            if cle == "NOM" and val == "?":
                val = input(f"Entrez la valeur pour {noeud.tag}: ").strip()
            if cle == "NOM" and val:
                val = _cap_phrase(val)
            if cle != k:
                del noeud.attrib[k]
            noeud.attrib[cle] = val

    for enfant in list(noeud):
        if hasattr(enfant, "tag") and isinstance(enfant.tag, str):
            enfant.tag = enfant.tag.strip().upper()
            if enfant.tag == "NOM":
                t = (enfant.text or "").strip()
                if t == "?":
                    t = input(f"Entrez la valeur pour {noeud.tag}: ").strip()
                enfant.text = _cap_phrase(t)
        uniformiser(enfant)

def extraire_attributs(noeud, supprimer_pseudo: bool = False):
    """
    Rassemble les attributs d’un nœud (attributs XML + pseudo-nœuds NOM/DESCRIPTION).
    Règles :
    - Doublon entre attribut et pseudo-nœud → nœud invalidé (return None)
    - Attribut inconnu (hors schéma) → ignoré mais nœud conservé
    - Si supprimer_pseudo=True → retire les pseudo-nœuds consommés du DOM
    """
    if not hasattr(noeud, "tag") or not isinstance(noeud.tag, str):
        return {}
    tagu = noeud.tag.strip().upper()

    if tagu in PLURIEL:
        return {}

    attr_spec = SCHEMA.get(tagu, {}).get("attrs", {})
    autorises = set(attr_spec.get("required", []) + attr_spec.get("optional", []))
    autorises.update({"NOM", "DESCRIPTION"})

    attrs = {}
    pseudo_a_supprimer = []
    pseudo_vus = set()

    # Attributs directs
    if getattr(noeud, "attrib", None):
        for k, v in list(noeud.attrib.items()):
            cle = (k or "").strip().upper()
            val = (v or "").strip()
            if cle not in autorises:
                print(f"{erreurs[10].replace('{attr}', cle).replace('{tag}', tagu)}")
                continue
            if cle == "NOM" and val:
                val = _cap_phrase(val)
            attrs[cle] = val

    # Pseudo-nœuds <NOM>/<DESCRIPTION>
    for enfant in list(noeud):
        if not hasattr(enfant, "tag") or not isinstance(enfant.tag, str):
            continue
        ctag = enfant.tag.strip().upper()
        if ctag not in {"NOM", "DESCRIPTION"}:
            continue
        val = (enfant.text or "").strip()
        if ctag == "NOM" and val == "?":
            val = input(f"Entrez la valeur pour {tagu}: ").strip()
        if ctag == "NOM":
            val = _cap_phrase(val)

        if ctag in attrs:
            print(f"{erreurs[11].replace('{cle}', ctag).replace('{tag}', tagu)}")
            return None

        if ctag in pseudo_vus:
            print(f"{erreurs[9].replace('{attrs}', ctag).replace('{tag}', tagu)}")
            return None

        pseudo_vus.add(ctag)
        attrs[ctag] = val
        pseudo_a_supprimer.append(enfant)

    if supprimer_pseudo:
        for p in pseudo_a_supprimer:
            try:
                noeud.remove(p)
            except Exception:
                pass

    return attrs

def valider_xml(racine):
    """
    Applique les règles de validation au DOM et marque les nœuds à ignorer.
    Cas gérés :
    - Nœud hors schéma → ignorer le nœud et ses descendants
    - Requis manquants → ignorer le nœud et ses descendants
    - Doublon attr/pseudo (renvoyé par extraire_attributs=None) → ignorer nœud+desc
    - Profondeur de sous-tâches au-delà de la limite → ignorer nœud+desc
    Renvoie un set d’identifiants 'id(node)' à exclure lors du parcours.
    """
    invalides = set()

    def inval_desc(n):
        for c in list(n):
            if hasattr(c, "tag") and isinstance(c.tag, str):
                invalides.add(id(c))
                inval_desc(c)

    def visite(n, profondeur_sous=0, parent_is_activity=False):
        if not hasattr(n, "tag") or not isinstance(n.tag, str):
            return
        tagu = n.tag.strip().upper()

        if tagu in {"NOM", "DESCRIPTION"}:
            return

        if tagu in PLURIEL:
            for c in list(n):
                if id(c) not in invalides:
                    visite(c, profondeur_sous, parent_is_activity=False)
            return

        if tagu not in SCHEMA:
            print(f"{erreurs[8].replace('{node}', tagu)}")
            invalides.add(id(n)); inval_desc(n); return

        is_activity = (tagu == "ACTIVITE")
        next_depth = (profondeur_sous + 1) if (is_activity and parent_is_activity) else (1 if is_activity else profondeur_sous)
        if is_activity and next_depth > SOUS_TACHE_PROFONDEUR_MAX:
            print(f"{erreurs[13].replace('{max}', str(SOUS_TACHE_PROFONDEUR_MAX))}")
            invalides.add(id(n)); inval_desc(n); return

        attrs = extraire_attributs(n, supprimer_pseudo=False)
        if attrs is None:
            invalides.add(id(n)); inval_desc(n); return

        required = SCHEMA[tagu]["attrs"]["required"]
        manquants = [a for a in required if not (attrs.get(a) or "").strip()]
        if manquants:
            print(f"{erreurs[7].replace('{attrs}', ','.join(manquants)).replace('{tag}', tagu)}")
            invalides.add(id(n)); inval_desc(n); return

        for c in list(n):
            if id(c) not in invalides:
                visite(c, next_depth, parent_is_activity=is_activity)

    visite(racine)
    return invalides

def afficher_creation(schema_obj, gid, attrs_map, attrs_src, node_name=None, verbose=False):
    """
    Résumé lisible après création (utile pour les journaux).
    """
    node_type = node_name or next((k for k, v in SCHEMA.items() if v is schema_obj), "INCONNU")
    nom = attrs_map.get("name", attrs_src.get("NOM", "SansNom"))
    print(f"{node_type} créé : '{nom}' (GID: {gid})")
    if verbose:
        attr_spec = schema_obj.get("attrs", {})
        required = attr_spec.get("required", [])
        optional = attr_spec.get("optional", [])
        for cle in required + optional:
            if cle in attrs_src:
                print(f"{cle:<12}: {attrs_src[cle]}")
    print("─" * 40)

def afficher_structure_xml(node, depth_sub=0, parent_is_activity=False, verbose=False, ancestors_last=None):
    """
    Affiche l’arborescence XML avec préfixes visuels et vérifications minimales.
    N’affiche que les nœuds conformes au schéma ou aux conteneurs pluriels.
    """
    if ancestors_last is None:
        ancestors_last = []
    if not hasattr(node, "tag") or not isinstance(node.tag, str):
        return

    node_type = node.tag.upper()

    if node_type not in SCHEMA and node_type not in PLURIEL:
        return

    is_activity = (node_type == "ACTIVITE")

    next_depth_sub = (depth_sub + 1) if (is_activity and parent_is_activity) else (1 if is_activity else depth_sub)
    if is_activity and next_depth_sub > SOUS_TACHE_PROFONDEUR_MAX:
        prefix = ""
        for last in ancestors_last:
            prefix += ("    " if last else "│   ")
        print(prefix + f"{erreurs[13].replace('{max}', str(SOUS_TACHE_PROFONDEUR_MAX))}")
        return

    attrs_src = extraire_attributs(node, supprimer_pseudo=False)
    if attrs_src is None:
        return

    known_attrs = []
    spec = SCHEMA.get(node_type, {}).get("attrs", {})
    allowed = set(spec.get("required", []) + spec.get("optional", []) + ["NOM", "DESCRIPTION"])
    for k, v in (attrs_src or {}).items():
        if k in allowed and v != "":
            known_attrs.append(f'{k}="{v}"')
    attrs_str = " ".join(known_attrs)

    prefix = ""
    if ancestors_last:
        for last in ancestors_last[:-1]:
            prefix += ("    " if last else "│   ")
        prefix += ("└── " if ancestors_last[-1] else "├── ")
    else:
        prefix = "└── "

    print(prefix + node_type + (f" ({attrs_str})" if attrs_str else ""))

    required = spec.get("required", [])
    manquants = [a for a in required if a not in (attrs_src or {}) or not (attrs_src.get(a) or "").strip()]
    if manquants:
        print(prefix + "    " + erreurs[7].replace("{attrs}", ",".join(manquants)).replace("{tag}", node_type))
        return

    children = [c for c in node if hasattr(c, "tag") and isinstance(c.tag, str) and (c.tag.upper() in SCHEMA or c.tag.upper() in PLURIEL)]
    total = len(children)

    for i, child in enumerate(children):
        is_last = (i == total - 1)
        afficher_structure_xml(
            child,
            depth_sub=next_depth_sub,
            parent_is_activity=is_activity,
            verbose=verbose,
            ancestors_last=ancestors_last + [is_last]
        )

# ----------------------------------------------------------------------
# Utilitaires Asana
# ----------------------------------------------------------------------
def _obtenir(obj, cle):
    """
    Accès uniforme aux champs d’un dict ou d’un objet renvoyé par le SDK.
    """
    if isinstance(obj, dict):
        return obj.get(cle)
    return getattr(obj, cle, None)

def gerer_erreur_api(e: ApiException, contexte="Asana"):
    """
    Traduit les statuts HTTP Asana en messages clairs et cohérents.
    """
    statut = getattr(e, "status", None)
    if statut == 400: print(erreurs[19])
    elif statut == 401: print(erreurs[20]); sys.exit(1)
    elif statut == 403: print(erreurs[21]); sys.exit(1)
    elif statut == 404: print(erreurs[22])
    elif statut == 409: print(erreurs[23])
    elif statut == 429: print(erreurs[24]); sys.exit(1)
    elif statut in (500, 501, 502, 503): print(erreurs[25]); sys.exit(1)
    else:
        print(f"{types_erreurs[1]}: erreur API {contexte} ({statut}) : {e}")

def mapper_attributs(type_noeud, attrs):
    """
    Transforme les attributs normalisés du XML vers les payloads attendus par Asana.
    """
    t = type_noeud.upper()
    m = {}
    if t == "PROJET":
        m["name"] = (attrs.get("NOM") or "").strip()
        m["public"] = (attrs.get("ACCÈS") or ACCES_DEFAUT).lower() == "public"
        vue = (attrs.get("VUE") or VUE_DEFAUT).lower()
        m["layout"] = "board" if vue in ("board", "tableau") else "list"
        notes = []
        if attrs.get("VERSION"): notes.append(f"Version: {attrs['VERSION']}")
        if attrs.get("DESCRIPTION"): notes.append(attrs["DESCRIPTION"])
        if notes: m["notes"] = "\n".join(notes)
    elif t == "SECTION":
        m["name"] = (attrs.get("NOM") or "").strip()
    elif t == "ACTIVITE":
        m["name"] = (attrs.get("NOM") or "").strip()
        if attrs.get("DESCRIPTION"): m["notes"] = attrs["DESCRIPTION"]
    return m

# ----------------------------------------------------------------------
# Accès Asana : vérifications et créations
# ----------------------------------------------------------------------
class VerificateurAsana:
    """
    Méthodes de vérification d’existence pour projets et sections.
    """
    def __init__(self, projets_api, sections_api, taches_api):
        self.projets_api = projets_api
        self.sections_api = sections_api
        self.taches_api = taches_api

    def existe(self, type_noeud, nom, gid_espace=None, gid_projet=None):
        """
        Retourne le GID existant du projet/section si déjà présent.
        """
        try:
            if type_noeud == "PROJET" and gid_espace:
                for p in self.projets_api.get_projects_for_workspace(gid_espace, opts={"opt_fields": "name,gid"}):
                    if _obtenir(p, "name") == nom:
                        return _obtenir(p, "gid")
            if type_noeud == "SECTION" and gid_projet:
                for s in self.sections_api.get_sections_for_project(gid_projet, opts={"opt_fields": "name,gid"}):
                    if _obtenir(s, "name") == nom:
                        return _obtenir(s, "gid")
        except ApiException as e:
            gerer_erreur_api(e, "Vérification")
        return None

class CreateurAsana:
    """
    Création des objets Asana et placement exact des tâches.
    Les tâches top-level sont créées via requests avec memberships pour
    cibler la section correcte dès la création.
    """
    def __init__(self, projets_api, sections_api, taches_api, verificateur, pat):
        self.projets_api = projets_api
        self.sections_api = sections_api
        self.taches_api = taches_api
        self.verificateur = verificateur
        self.pat = pat

    def _gid_from_created(self, created):
        """
        Extrait le GID quel que soit le format de réponse (dict/objets SDK).
        """
        if isinstance(created, dict):
            return created.get("gid") or (created.get("data") or {}).get("gid")
        if hasattr(created, "gid"):
            return getattr(created, "gid")
        if hasattr(created, "data"):
            d = getattr(created, "data")
            if isinstance(d, dict):
                return d.get("gid")
            if hasattr(d, "gid"):
                return d.gid
        if hasattr(created, "to_dict"):
            d = created.to_dict()
            return d.get("gid") or (d.get("data") or {}).get("gid")
        return None

    def creer_projet(self, attrs, gid_espace):
        """
        Crée un projet s’il n’existe pas, sinon renvoie l’existant.
        """
        m = mapper_attributs("PROJET", attrs)
        existant = self.verificateur.existe("PROJET", m["name"], gid_espace=gid_espace)
        if existant:
            print(f"{types_erreurs[0]}: PROJET existe déjà (GID: {existant})")
            return existant
        try:
            body = {"data": {"name": m["name"], "workspace": gid_espace,
                             "public": m.get("public", False),
                             "notes": m.get("notes"),
                             "layout": m.get("layout", "list")}}
            created = self.projets_api.create_project(body, opts={})
            gid = self._gid_from_created(created)
            if gid:
                print(f"PROJET créé : '{m['name']}' (GID: {gid})")
                return gid
        except ApiException as e:
            gerer_erreur_api(e, "Création PROJET")
        return None

    def creer_section(self, attrs, gid_projet):
        """
        Crée une section si absente et retourne son GID.
        """
        m = mapper_attributs("SECTION", attrs)
        existant = self.verificateur.existe("SECTION", m["name"], gid_projet=gid_projet)
        if existant:
            print(f"{types_erreurs[0]}: SECTION existe déjà (GID: {existant})")
            return existant
        try:
            headers = {"Authorization": f"Bearer {self.pat}", "Content-Type": "application/json"}
            created = self.sections_api.api_client.call_api(
                f"/projects/{gid_projet}/sections",
                "POST",
                body={"data": {"name": m["name"]}},
                response_type="object",
                auth_settings=[],
                header_params=headers
            )
            data = created[0] if isinstance(created, tuple) else created
            gid = data.get("gid") or (data.get("data") or {}).get("gid")
            if gid:
                print(f"SECTION créée : '{m['name']}' (GID: {gid})")
                return gid
        except ApiException as e:
            gerer_erreur_api(e, "Création SECTION")
        except Exception as e:
            print(f"{types_erreurs[1]}: erreur inattendue lors de la création de la SECTION '{m['name']}': {e}")
        return None

    def creer_tache_top(self, attrs, gid_espace, gid_projet, gid_section):
        """
        Crée une tâche top-level déjà rattachée au projet et à la section cible.
        """
        m = mapper_attributs("ACTIVITE", attrs)
        headers = {"Authorization": f"Bearer {self.pat}", "Content-Type": "application/json"}
        body = {
            "data": {
                "name": m["name"],
                "workspace": gid_espace,
                "memberships": [{"project": gid_projet, "section": gid_section}],
            }
        }
        if m.get("notes"):
            body["data"]["notes"] = m["notes"]

        try:
            r = requests.post("https://app.asana.com/api/1.0/tasks", json=body, headers=headers, timeout=30)
            if not r.ok:
                print(f"{types_erreurs[1]}: création tâche '{m['name']}' échouée ({r.status_code}) : {r.text}")
                return None
            data = r.json().get("data", {})
            gid = data.get("gid")
            if gid:
                print(f"ACTIVITE créée : '{m['name']}' (GID: {gid})")
            return gid
        except Exception as e:
            print(f"{types_erreurs[1]}: erreur inattendue lors de la création de la tâche '{m['name']}': {e}")
            return None

    def creer_sous_tache(self, attrs, gid_parent):
        """
        Crée une sous-tâche (sans section), attachée à la tâche parente.
        """
        m = mapper_attributs("ACTIVITE", attrs)
        try:
            body = {"data": {"name": m["name"], "parent": gid_parent}}
            if m.get("notes"):
                body["data"]["notes"] = m["notes"]
            created = self.taches_api.create_task(body, opts={})
            gid = self._gid_from_created(created)
            if gid:
                print(f"SOUS-ACTIVITE créée : '{m['name']}' (GID: {gid})")
            return gid
        except ApiException as e:
            gerer_erreur_api(e, "Création SOUS-ACTIVITE")
            return None

    def nettoyer_sections_placeholders_vides(self, gid_projet: str):
        """
        Supprime les sections de type “placeholder” uniquement si elles sont vides.
        Évite la suppression de sections contenant des tâches.
        """
        try:
            placeholders = {
                "", " ", "untitled section", "section", "first section",
                "sans titre", "par défaut", "default", "no section"
            }
            sections = self.sections_api.get_sections_for_project(
                gid_projet, opts={"opt_fields": "name,gid"}
            )

            for sec in sections:
                nom = (_obtenir(sec, "name") or "").strip().lower()
                gid = _obtenir(sec, "gid")
                if nom not in placeholders:
                    continue

                try:
                    tasks_in_section = self.sections_api.get_tasks_for_section(
                        gid, opts={"opt_fields": "gid"}, limit=1
                    )
                    is_empty = (len(list(tasks_in_section)) == 0)
                except ApiException as e:
                    print(f"{types_erreurs[0]}: impossible de vérifier le contenu de la section '{nom}' ({gid}).")
                    continue

                if is_empty:
                    try:
                        self.sections_api.delete_section(gid)
                        print(f"🧹 Section placeholder supprimée: '{nom or '«sans nom»'}' (GID: {gid})")
                    except ApiException as e:
                        print(f"{types_erreurs[1]}: suppression section placeholder échouée ({gid}) : {e}")
        except ApiException as e:
            gerer_erreur_api(e, "Nettoyage sections placeholder")

# ----------------------------------------------------------------------
# Parcours XML → Asana
# ----------------------------------------------------------------------
def afficher(noeud, prefix=""):
    """
    Affiche une version minimale hiérarchique du DOM (dry-run).
    """
    if not hasattr(noeud, "tag") or not isinstance(noeud.tag, str):
        return
    tagu = noeud.tag.strip().upper()
    print(f"{prefix}{tagu}")
    for c in list(noeud):
        afficher(c, prefix + "  ")

def parcourir_xml(noeud, createur: CreateurAsana,
                  gid_espace, gid_projet=None, gid_section=None,
                  gid_parent_tache=None, invalides=None, dry_run=False, profondeur_sous=0):
    """
    Parcours récursif de l’arbre :
    - PROJET : création puis descente vers les SECTIONS
    - SECTION : création puis descente vers les ACTIVITES top-level
    - ACTIVITE top-level : création de tâche rattachée au projet+section
    - ACTIVITE enfant : création de sous-tâche sous le parent
    """
    if invalides is None:
        invalides = set()

    if not hasattr(noeud, "tag") or not isinstance(noeud.tag, str):
        return
    if id(noeud) in invalides:
        return

    tagu = noeud.tag.strip().upper()

    if tagu in PLURIEL:
        for c in list(noeud):
            if id(c) not in invalides:
                parcourir_xml(c, createur, gid_espace, gid_projet, gid_section, gid_parent_tache, invalides, dry_run, profondeur_sous)
        return

    attrs = extraire_attributs(noeud, supprimer_pseudo=not dry_run)
    if attrs is None:
        return

    if not (attrs.get("NOM") or "").strip():
        print(f"{erreurs[7].replace('{attrs}', 'NOM').replace('{tag}', tagu)}")
        return

    if dry_run:
        prefix = "│   " * (profondeur_sous if tagu == "ACTIVITE" else 0)
        print(f"{prefix}└── {tagu} (NOM='{attrs.get('NOM')}'{', DESC' if attrs.get('DESCRIPTION') else ''})")
        for c in list(noeud):
            next_prof = profondeur_sous + 1 if tagu == "ACTIVITE" else profondeur_sous
            parcourir_xml(c, createur, gid_espace, gid_projet, gid_section, gid_parent_tache, invalides, True, next_prof)
        return

    gid_cree = None
    if tagu == "PROJET":
        gid_cree = createur.creer_projet(attrs, gid_espace)
        gid_projet = gid_cree or gid_projet
        for c in list(noeud):
            if id(c) not in invalides:
                parcourir_xml(c, createur, gid_espace, gid_projet=gid_projet, gid_section=None,
                            gid_parent_tache=None, invalides=invalides, dry_run=False, profondeur_sous=0)

        createur.nettoyer_sections_placeholders_vides(gid_projet)
        return
    
    if tagu == "SECTION":
        if not gid_projet:
            print(f"{types_erreurs[1]}: GID projet manquant pour SECTION '{attrs.get('NOM','?')}'")
            return
        gid_cree = createur.creer_section(attrs, gid_projet)
        gid_section = gid_cree or gid_section
        for c in list(noeud):
            if id(c) not in invalides:
                parcourir_xml(c, createur, gid_espace, gid_projet=gid_projet, gid_section=gid_section,
                              gid_parent_tache=None, invalides=invalides, dry_run=False, profondeur_sous=0)
        return

    if tagu == "ACTIVITE":
        if gid_parent_tache:
            gid_cree = createur.creer_sous_tache(attrs, gid_parent_tache)
            for c in list(noeud):
                if id(c) not in invalides:
                    parcourir_xml(c, createur, gid_espace, gid_projet=gid_projet, gid_section=None,
                                  gid_parent_tache=gid_cree, invalides=invalides, dry_run=False, profondeur_sous=profondeur_sous + 1)
        else:
            if not gid_projet or not gid_section:
                print(f"{types_erreurs[1]}: project/section GID manquant pour ACTIVITE '{attrs.get('NOM','?')}'")
                return
            gid_cree = createur.creer_tache_top(attrs, gid_espace, gid_projet, gid_section)
            for c in list(noeud):
                if id(c) not in invalides:
                    parcourir_xml(c, createur, gid_espace, gid_projet=gid_projet, gid_section=None,
                                  gid_parent_tache=gid_cree, invalides=invalides, dry_run=False, profondeur_sous=1)
        return

# === CLI / Main ===
parser = argparse.ArgumentParser(description="Création de projets, sections et activités Asana à partir de fichiers XML", add_help=False)
parser.add_argument("--f", nargs="*", help="Fichier(s) XML ou * pour tous les fichiers du dossier courant")
parser.add_argument("--p", nargs="*", help="Personal Access Token (PAT) Asana")
parser.add_argument("--w", nargs="*", help="Espace de travail Asana (facultatif, auto-détection si un seul)")
parser.add_argument("--verbose", action="store_true", help="Affiche les détails complets lors de la création")
parser.add_argument("--dry-run", action="store_true", help="Analyse uniquement le XML (aucun appel à Asana)")
parser.add_argument("-h", "--help", "-help", dest="help", action="store_true", help="Afficher les options valides et quitter")
args, unknown = parser.parse_known_args()

# Aide simple et sortie immédiate.
if args.help:
    if len(sys.argv) > 2:
        print(erreurs[1][3])
        sys.exit(0)
    usage = "usage: asana_final.py [-h] --f F [F ...] --p P [--w W] [--verbose] [--dry-run]"
    print(usage)
    print("\nCréation de projets, sections et activités Asana à partir de fichiers XML")
    print("\nOptions:\n  --f <files>    Fichier(s) XML ou * pour tous les fichiers du dossier courant\n"
          "  --p <PAT>      Personal Access Token (PAT) Asana\n"
          "  --w <workspace> Espace de travail Asana (facultatif — auto-sélection si un seul)\n"
          "  --verbose      Afficher les attributs détaillés lors de la création\n"
          "  --dry-run      N'analyser que le XML sans contacter Asana\n")
    sys.exit(0)

# Rejet des arguments inconnus.
if unknown:
    print(f"{types_erreurs[2]}: argument(s) inconnu(s): {' '.join(unknown)}")
    sys.exit(1)

# Validation des paramètres selon le mode.
if args.dry_run:
    if not args.f:
        fichier = input("Entrez le chemin du fichier XML à analyser : ").strip()
        if not fichier:
            sys.exit(erreurs[0])
        args.f = [fichier]
else:
    if not args.f or not args.p:
        sys.exit(erreurs[0])
    if len(args.f) == 0:
        sys.exit(erreurs[1][0])
    if len(args.p) != 1:
        sys.exit(erreurs[1][1])
    if args.w is not None and len(args.w) != 1:
        sys.exit(erreurs[1][2])

# Sélection des fichiers à traiter.
if args.f == ["*"]:
    fichiers = [f for f in os.listdir(".") if f.lower().endswith(".xml")]
else:
    fichiers = args.f if args.f else []

# Mode DRY-RUN : lecture et affichage sans appels Asana.
if args.dry_run:
    if not fichiers:
        fichier = input("Entrez le chemin du fichier XML à analyser : ").strip()
        if not fichier:
            print(erreurs[0])
            sys.exit(0)
        fichiers = [fichier]

    for fichier in fichiers:
        print(f"\nAnalyse (dry-run) du fichier: {fichier}")
        if not os.path.isfile(fichier):
            print(f"{erreurs[2].replace('{fichier}', fichier)}")
            continue
        if not fichier.lower().endswith(".xml"):
            print(f"{erreurs[4].replace('{fichier}', fichier)}")
            continue
        try:
            with open(fichier, encoding="utf-8") as f:
                try:
                    arbre = etree.parse(f, parser=etree.XMLParser(recover=True))
                except etree.XMLSyntaxError:
                    print(erreurs[5]); continue
        except UnicodeDecodeError as e:
            print(f"{erreurs[3].replace('{fichier}', fichier).replace('{error}', str(e))}"); continue
        except Exception as e:
            print(f"{erreurs[6].replace('{fichier}', fichier).replace('{error}', str(e))}"); continue

        racine = arbre.getroot()
        uniformiser(racine)

        tag_racine = racine.tag.strip().upper()
        if tag_racine not in ("PROJETS", "PROJET"):
            print(erreurs[12]); continue

        invalides = valider_xml(racine)

        if tag_racine == "PROJETS":
            for projet in racine.findall("PROJET"):
                afficher_structure_xml(projet, depth_sub=0, parent_is_activity=False, verbose=args.verbose)
        elif tag_racine == "PROJET":
            afficher_structure_xml(racine, depth_sub=0, parent_is_activity=False, verbose=args.verbose)

    sys.exit(0)

# Mode exécution réelle : configuration Asana.
PAT = args.p[0] if args.p else input("Entrez votre Personal Access Token (PAT) Asana : ").strip()
if not PAT:
    sys.exit(erreurs[14])

configuration = asana.Configuration()
configuration.access_token = PAT
client = asana.ApiClient(configuration)

users_api = asana.UsersApi(client)
projets_api = asana.ProjectsApi(client)
sections_api = asana.SectionsApi(client)
taches_api = asana.TasksApi(client)

try:
    me = users_api.get_user("me", {"opt_fields": "name,workspaces.name,workspaces.gid"})
    if not isinstance(me, dict) or "name" not in me or "workspaces" not in me:
        sys.exit(erreurs[16])
    print(f"\nConnexion établie avec l'utilisateur : {me['name']}\n")
except ApiException as e:
    gerer_erreur_api(e, contexte="Connexion"); sys.exit(1)
except Exception as e:
    sys.exit(erreurs[15].replace("{error}", str(e)))

espaces = me.get("workspaces", [])
if not espaces:
    sys.exit(erreurs[17].replace("{utilisateur}", me.get("name", "?")))

if args.w:
    espace = next((w for w in espaces if w['gid'] == args.w[0] or w['name'] == args.w[0]), None)
    if not espace:
        sys.exit(erreurs[18])
else:
    if len(espaces) == 1:
        espace = espaces[0]
        print(f"Seulement un espace de travail détecté pour {me['name']}")
    else:
        print(f"Plusieurs espaces de travail détectés pour {me['name']}")
        for i, w in enumerate(espaces, start=1):
            print(f"[{i}] {w['name']}")
        choix = None
        while choix is None:
            raw = input("Entrez le numéro de l'espace à utiliser: ").strip()
            if not raw.isdigit() or not (1 <= int(raw) <= len(espaces)):
                print(f"{types_erreurs[0]}: choix invalide, réessayez")
                continue
            choix = int(raw)
        espace = espaces[choix - 1]

gid_espace = str(espace.get("gid"))
nom_espace = espace.get("name")
print(f"Espace de travail sélectionné : {nom_espace} (GID: {gid_espace})")

verificateur = VerificateurAsana(projets_api, sections_api, taches_api)
createur = CreateurAsana(projets_api, sections_api, taches_api, verificateur, PAT)

if not fichiers:
    print(erreurs[0]); sys.exit(0)

# Exécution réelle : lecture, validation, puis création Asana.
for fichier in fichiers:
    print(f"\nTraitement du fichier : {fichier}")
    if not os.path.isfile(fichier):
        print(f"{erreurs[2].replace('{fichier}', fichier)}"); continue
    if not fichier.lower().endswith(".xml"):
        print(f"{erreurs[4].replace('{fichier}', fichier)}"); continue
    try:
        with open(fichier, encoding="utf-8") as f:
            try:
                arbre = etree.parse(f, parser=etree.XMLParser(recover=True))
            except etree.XMLSyntaxError:
                print(erreurs[5]); continue
    except UnicodeDecodeError as e:
        print(f"{erreurs[3].replace('{fichier}', fichier).replace('{error}', str(e))}"); continue
    except Exception as e:
        print(f"{erreurs[6].replace('{fichier}', fichier).replace('{error}', str(e))}"); continue

    racine = arbre.getroot()
    uniformiser(racine)

    tag_racine = racine.tag.strip().upper()
    if tag_racine not in ("PROJETS", "PROJET"):
        print(erreurs[12]); continue

    invalides = valider_xml(racine)

    if tag_racine == "PROJETS":
        for projet in racine.findall("PROJET"):
            parcourir_xml(
                projet,
                createur,
                gid_espace,
                gid_projet=None,
                gid_section=None,
                gid_parent_tache=None,
                invalides=invalides,
                dry_run=False,
                profondeur_sous=0
            )
    elif tag_racine == "PROJET":
        parcourir_xml(
            racine,
            createur,
            gid_espace,
            gid_projet=None,
            gid_section=None,
            gid_parent_tache=None,
            invalides=invalides,
            dry_run=False,
            profondeur_sous=0
        )

print("\n Traitement terminé.\n")