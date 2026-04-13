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

# Je commence par lire le premier paramètre avec Get-Content.
# Aussi, j'enlève le premier caractère (de la première ligne) s’il débute avec "#".
$lignes = Get-Content -Path $chemin_fich
if ($lignes[0].StartsWith('#')) {
    $lignes[0] = $lignes[0].Substring(1).Trim()
}

# J'utilise ConvertFrom-Csv pour transformer le contenu séparé par le délimiteur ";" en objet de type PSObject.
$users = $lignes | ConvertFrom-Csv -Delimiter ";"

# Détermine si le système est joint à un domaine (renvoie True ou False)
$systemType = (Get-WmiObject Win32_ComputerSystem).PartOfDomain

# Fonction pour créer un utilisateur local avec mot de passe et groupe
Function CreateLocalUser {
    param (
        [string]$username,
        [string]$prenom,
        [string]$nom,
        [string]$empno,
        [string]$dept,
        [string]$dateFin,
        [string]$groupe
    )
        
    # Génération du mot de passe en utilisant les deux listes et les trois derniers chiffres du numéro d'employé:
    $motdp = GeneratePassword -empno $empno
    $motdps = convertto-securestring $motdp -asplaintext -force

    # Création de l'utilisateur avec ou sans expiration de compte selon la présence d'une date de fin de contrat:
    if ([string]::IsNullOrWhiteSpace($dateFin)) {
        New-LocalUser -Name $username -Password $motdps -Description "$empno $dept" -FullName "$prenom $nom"
    } else {
        New-LocalUser -Name $username -Password $motdps -Description "$empno $dept" -AccountExpires (Get-Date $dateFin)
    }
        
    # On définit que l'utilisateur devra changer son mot de passe lors de la première connexion.
    net user $username /logonpasswordchg:yes /passwordreq:yes

    # Si l’utilisateur appartient au groupe « Admin », il est ajouté au groupe des administrateurs (LOCAL).
    # Sinon, si le groupe n’existe pas, on crée le groupe (LOCAL). 
    if ($groupe -eq "Admin") {
        $groupe = "Administrators"
    } else {
        if (-not (Get-LocalGroup -Name $groupe -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $groupe
        }
    }
    # L'utilisateur est ajouté au groupe auquel il appartient.
    add-localgroupmember -group $groupe -member $username

    # Confirmation de la création de l'utilisateur avec l'affichage de son nom d'utilisateur et son mot de passe
    Write-Output "L'utilisateur (LOCAL) $username ayant le mot de passe $motdp a été créé."
}

# Fonction pour créer un utilisateur Active Directory avec mot de passe et groupe
Function CreateADUser {
    param (
        [string]$username,
        [string]$prenom,
        [string]$nom,
        [string]$empno,
        [string]$dept,
        [string]$dateFin,
        [string]$groupe
    )

    $chemin = "CN=Users,DC=example,DC=com"

    # Génération du mot de passe en utilisant les deux listes et les trois derniers chiffres du numéro d'employé:
    $motdp = GeneratePassword -empno $empno
    $motdps = ConvertTo-SecureString $motdp -AsPlainText -Force

    # Crée un nouvel utilisateur dans Active Directory
    New-ADUser -Name "$username" `
        -SamAccountName $username `
        -UserPrincipalName "$username@example.com" `
        -GivenName $prenom `
        -Surname $nom `
        -DisplayName "$prenom $nom" `
        -EmailAddress "$username@example.com" `
        -EmployeeNumber $empno `
        -Description "Projet synthèse A" `
        -Department $dept `
        -Company "Example Organization" `
        -PasswordNeverExpires $false `
        -AccountPassword $motdps `
        -ChangePasswordAtLogon $true `
        -Enabled $true

    # Si une date de fin de contrat est spécifiée, on la définit comme expiration du compte
    if (-not [string]::IsNullOrWhiteSpace($dateFin)) {
        Set-ADUser -Identity $username -AccountExpirationDate (Get-Date $dateFin)
    }

    # Si l’utilisateur appartient au groupe « Admin », il est ajouté au groupe des administrateurs (AD).
    # Sinon, si le groupe n’existe pas, on crée le groupe (AD). 
    if ($groupe -eq "Admin") {
        $groupe = "Administrators"
    } else {
        if (-not (Get-ADGroup -Filter "Name -eq '$groupe'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $groupe -GroupCategory Distribution -GroupScope Global `
                -Path "$chemin" `
                -Description "$groupe group"
        }
    }
    # Si l'utilisateur existe, ce dernier est ajouté au groupe.
    $user = Get-ADUser -Identity $username -ErrorAction SilentlyContinue
    if ($user) {
        Add-ADGroupMember -Identity $groupe -Members $user
    } else {
        Write-Warning "L'utilisateur $username est introuvable. Impossible de l'ajouter au groupe $groupe."
    }

    # Confirmation de la création de l'utilisateur avec l'affichage de son nom d'utilisateur et son mot de passe
    Write-Output "L'utilisateur (AD) $username ayant le mot de passe $motdp a été créé."
}

# Fonction pour vérifier si un nom d'utilisateur est déjà pris dans l'AD et/ou localement selon le type de système
function VerifyUsername {
    param (
        [string]$username,
        [string]$system,
        [bool]$domainJoined
    )

    # Cas où c'est un système Local uniquement
    if ($system -eq "Local") {
        $exists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
        return @{ IsTaken = [bool]$exists; VerificationValid = $true }
    }

    # Cas où c'est un système AD uniquement
    elseif ($system -eq "AD") {
        if (-not $domainJoined) {
            #La création du nom d'utilisateur unique se termine, car il n'y a pas d'utilisateurs AD
            return @{ IsTaken = $false; VerificationValid = $false }
        }
        $exists = Get-ADUser -Filter { SamAccountName -eq $username } -ErrorAction SilentlyContinue
        # Retourne un dictionnaire avec l’état de disponibilité du nom d’utilisateur
        return @{ IsTaken = [bool]$exists; VerificationValid = $true }
    }

    # Cas Local-AD (les deux)
    elseif ($system -eq "Local-AD") {
        if (-not $domainJoined) {
            # Vérifie si un utilisateur local avec ce nom existe déjà
            $exists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
            # Retourne un dictionnaire avec l’état de disponibilité du nom d’utilisateur
            return @{ IsTaken = [bool]$exists; VerificationValid = $true }
        }
        else {
            # Vérifie si un utilisateur AD avec ce nom existe déjà
            $adExists = Get-ADUser -Filter { SamAccountName -eq $username } -ErrorAction SilentlyContinue
            # Retourne un dictionnaire avec l’état de disponibilité du nom d’utilisateur
            return @{ IsTaken = ([bool]$localExists -or [bool]$adExists); VerificationValid = $true }
        }
    }

    # Type de système invalide : la vérification échoue
    return @{ IsTaken = $false; VerificationValid = $false }
}

# Fonction pour créer un mot de passe unique
Function GeneratePassword {
    param (
        [string]$empno
    )

    # Ici, je fabrique deux listes qui seront utilisées plus tard pour créer un mot de passe unique pour chaque utilisateur.
    $mot = @("Soleil", "Fraise", "Crayon")
    $symbole = @("$", "%", "!")
    return "$($mot | Get-Random)$($symbole | Get-Random)$($empno.ToString().Substring($empno.Length - 3))"
}

# Voici la boucle pour traiter chaque utilisateur un à la fois.
foreach ($user in $users) {
    # Ici, je stocke les valeurs de chaque colonne du fichier .csv importé dans une variable qui lui correspond et je remplace les lettres majuscules du prénom et du nom par des lettres minuscules.
    $system = $user.Système
    $prenom = $user.Prénom.ToLower()
    $nom = $user.Nom.ToLower()
    $empno = $user.NoEmployé
    $dept = $user.Département
    $dateFin = $user.DateFinContrat
    $groupe = $user.Groupe

    # Génère un nom d’utilisateur de la forme prenom+nom, en commençant par une lettre du prénom
    $debut_lettre = 1
    $success = $true
    $verification = $true
    $username = "$($prenom.Substring(0,$debut_lettre))$nom"

    # Boucle jusqu’à ce qu’un nom d'utilisateur soit disponible ou qu’on manque de lettres dans le prénom
    while ($true) {
        $resultat = VerifyUsername -username $username -system $system -domainJoined $systemType
        if (-not $resultat.VerificationValid) {
            Write-Output "Vérification impossible pour $username — système incompatible."
            $verification = $false
            $success = $false
            break
        }

        if (-not $resultat.IsTaken) {
            break  # nom libre, sortir
        }

        if ($debut_lettre -lt $prenom.Length) {
            $debut_lettre++
            $username = "$($prenom.Substring(0,$debut_lettre))$nom"
            Write-Output "Tentative de création de compte avec la combinaison de $prenom $nom; $username"
        } else {
            Write-Output "Impossible de créer un utilisateur avec la combinaison $prenom $nom; $username"
            $success = $false
            break
        }
    }

    # Condition après la boucle pour passer au prochain employé
    if (-not $success -or -not $verification) {
        continue
    } else {
        # Création des comptes selon que le système est joint à un domaine ou non
        if ($systemType) {
            # Si on est dans un domaine ;
            switch ($system) {
                "AD" {
                    # Créer un compte AD seulement
                    CreateADUser -username $username -groupe $groupe -dateFin $dateFin -prenom $prenom -nom $nom -empno $empno -dept $dept
                }
                "Local-AD" {
                    # Créer un compte AD
                    CreateADUser -username $username -groupe $groupe -dateFin $dateFin -prenom $prenom -nom $nom -empno $empno -dept $dept
                }
                "Local" {
                    # Créer un compte local seulement
                    Write-Output "Système joint à un domaine — compte LOCAL ignoré: $username"
                }
                default {
                    Write-Output "Type de système inconnu: $system"
                }
            }
        } else {
            # Si on n’est PAS dans un domaine ;
            switch ($system) {
                "Local" {
                    # Créer un compte local seulement
                    CreateLocalUser -username $username -groupe $groupe -dateFin $dateFin -prenom $prenom -nom $nom -empno $empno -dept $dept
                }
                "Local-AD" {
                    # Créer seulement la partie locale (on ignore la partie AD)
                    CreateLocalUser -username $username -groupe $groupe -dateFin $dateFin -prenom $prenom -nom $nom -empno $empno -dept $dept
                }
                "AD" {
                    # Ignorer les comptes AD si on n’est pas joint à un domaine
                    Write-Output "Système non joint à un domaine — compte AD ignoré: $username"
                }
                default {
                    Write-Output "Type de système inconnu: $system"
                }
            }
        }
    }
}