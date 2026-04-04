#Voici les paramètres exigés:
#J'utilise mandatory=true pour que la présence de chaque paramètre soit obligatoire.
param (
    [Parameter(Mandatory=$true)]
    [string]$PrenomEmploye,

    [Parameter(Mandatory=$true)]
    [string]$NomEmploye,

    [Parameter(Mandatory=$true)]
    [string]$NoEmploye
)

#Je combine le prénom avec le nom dans une variable pour, plus tard, comparer cette variable au nom complet de l'utilisateur et voir s'il existe.
$nomcomplet = "$PrenomEmploye $NomEmploye"
#Je recherche si le numéro d'employé spécifié dans un des paramètres correspond à celui dans la description de l'utilisateur.
$descriptionattendue = "NoEmployé:$NoEmploye"

#Je stocke le numéro d'employé situé dans la description de l'utilisateur, et le nom complet de l'utilisateur dans la variable utilisateur.
#Si l'information de l'utilisateur (numéro employé et nom complet) ne correspond pas à celle d'un utilisateur, la variable aura une valeur nulle.
$utilisateur = Get-LocalUser | Where-Object {
    $_.Description -like "*$descriptionattendue*" -and
    $_.FullName -like "*$nomcomplet*"
}

#Si la variable de l'utilisateur est vraie (c'est-à-dire qu'elle n'est pas nulle), j'utilise la commande disable-localuser pour désactiver le compte.
#En revanche, si la variable de l'utilisateur est fausse (nulle), car un ou plusieurs paramètres spécifiés ne correspondent pas à un utilisateur, un message d'erreur sera affiché.
if ($utilisateur) {
    Disable-LocalUser -Name $utilisateur.Name
} else {
    Write-Host "Ce compte n’existe pas: $nomcomplet - $NoEmploye"
}