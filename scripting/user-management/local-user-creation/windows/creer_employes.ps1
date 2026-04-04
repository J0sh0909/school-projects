# Voici le paramètre qui prend en charge le chemin du fichier .csv:
param (
    [string]$chemin_fich
)

# Je vérifie si le chemin fourni existe; sinon, le fichier est cherché dans le dossier Documents de l'utilisateur.
# Et, si le fichier est toujours introuvable, une erreur est affichée et arrête le script.
if (-not (Test-Path $chemin_fich)) {
    $nom_fich = Split-Path $chemin_fich -Leaf
    $chemin_doc = Join-Path -Path "$HOME\Documents" -ChildPath $nom_fich
    if (Test-Path $chemin_doc) {
        $chemin_fich = $chemin_doc
    } else {
        Write-Output "Erreur : Le fichier CSV '$chemin_fich' est introuvable, même dans Documents."
        exit 1
    }
}

# Ici, je fabrique deux listes qui seront utilisées plus tard pour créer un mot de passe unique pour chaque utilisateur.
$mot = @("Soleil", "Fraise", "Crayon")
$symbole = @("$", "%", "!")

# Je commence par lire le premier paramètre avec Get-Content.
# Aussi, j'enlève le premier caractère (de la première ligne) s’il débute avec "#".
$lignes = Get-Content -Path $chemin_fich
if ($lignes[0].StartsWith('#')) {
    $lignes[0] = $lignes[0].Substring(1).Trim()
}

# J'utilise ConvertFrom-Csv pour transformer le contenu séparé par le délimiteur ";" en objet de type PSObject.
$users = $lignes | ConvertFrom-Csv -Delimiter ";"

# Voici la boucle pour traiter chaque utilisateur un à la fois.
foreach ($user in $users) {
    # Ici, je stocke les valeurs de chaque colonne du fichier .csv importé dans une variable qui lui correspond et je remplace les lettres majuscules du prénom et du nom par des lettres minuscules.
    $prenom = $user.Prénom.ToLower()    # Prénom de l'utilisateur
    $nom = $user.Nom.ToLower()  # Nom de l'utilisateur
    $empno = $user.NoEmployé    # Numéro d'employé
    $dept = $user.Département   # Département de l'utilisateur
    $dateFin = $user.DateFinContrat # Date de fin de contrat de l'utilisateur (optionnel)
    $groupe = $user.Groupe  # Groupe auquel l'utilisateur appartient

    # Voici les variables utilisées pour générer un nom d’utilisateur unique :
    # - $debut_lettre : le compteur de lettres prises du prénom
    # - $success : un indicateur pour savoir si un nom unique a été trouvé
    # - $username : le nom d’utilisateur en cours de test
    # - $userExists : la commande pour vérifier si le nom d’utilisateur existe déjà
    $debut_lettre = 1
    $success = $true
    $username = "$($prenom.Substring(0,1))$nom"
    $userExists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue

    # La boucle fonctionne comme suit: tant que l'utilisateur existe, ajoute une lettre de plus (du prénom) à son nom d'utilisateur jusqu'au point que ce dernier ne possède plus de lettre pour créer un nom d'utilisateur unique.
    while ($userExists) {
        if ($debut_lettre -lt $prenom.length) {
            $username = "$($prenom.Substring(0,$debut_lettre + 1))$nom"
            Write-Output "Tentative de création de compte avec la combinaison de $prenom $nom; $username"
        } else {
            Write-Output "Impossible de créer un utilisateur avec la combinaison $prenom $nom; $username"
            $success = $false
            break
        }
        $debut_lettre++
        $userExists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
    }

    # Si la création du nom d'utilisateur unique échoue, passe au prochain utilisateur ; sinon, exécute le reste des commandes associées à ce dernier.
    if ($success -eq $false) {
        continue
    } else {
        # Si l’utilisateur appartient au groupe « Admin », l’ajouté au groupe des administrateurs ;
        if ($groupe -eq "Admin") {
            $groupe = "Administrators"
        }

        # Si le groupe n’existe pas, le groupe est créé ;
        if (-not (Get-LocalGroup -Name $groupe -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $groupe
        }

        # Génération du mot de passe à l'aide des deux listes et des trois derniers chiffres du numéro d'employé ;
        $motdp = "$($mot | get-random)$($symbole | get-random)$($empno.ToString().substring($empno.ToString().length - 3))"
        $motdps = convertto-securestring $motdp -asplaintext -force

        # Création de l'utilisateur avec ou sans expiration de compte ;
        if ([string]::IsNullOrWhiteSpace($dateFin)) {
            New-LocalUser -Name $username -Password $motdps -Description "$empno $dept" -FullName "$prenom $nom"
        } else {
            New-LocalUser -Name $username -Password $motdps -Description "$empno $dept" -AccountExpires (Get-Date $dateFin) -FullName "$prenom $nom"
        }

        # Si l'utilisateur a été créé, configure le mot de passe à changer au premier login et l'ajoute au groupe ;
        if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
            net user $username /logonpasswordchg:yes /passwordreq:yes
            add-localgroupmember -group $groupe -member $username
            Write-Output "L'utilisateur $username ayant le mot de passe $motdp a été créé."
        }
    }
}