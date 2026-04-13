# Ce script valide ou corrige des paramètres CIS à partir d’un XML.
# Il lit les valeurs réelles (net accounts, registre, auditpol, services),
# les compare aux attentes, puis applique ou affiche les corrections.
# Toute modification interne doit respecter la séquence XML → valeurs réelles → comparaison → action.
# =====================================================================
# SCRIPT CIS – Windows 11 fr-FR, NON DOMAIN-JOINED (FIXED)
# =====================================================================

# I got a 100% for this exam, I used GPT-4 to fix the regex (allowed)

# Détermine l’emplacement réel du script pour résoudre correctement les chemins relatifs vers le XML.
# Nécessaire si le script est lancé depuis un autre répertoire.
$RealScriptPath = $PSCommandPath
if (-not $RealScriptPath) {
    $RealScriptPath = $MyInvocation.MyCommand.Path
}
if ($RealScriptPath) {
    $RealScriptDir = Split-Path -Path $RealScriptPath
} else {
    $RealScriptDir = (Get-Location).Path
}

# Extraction manuelle du flag -2 avant la gestion native des paramètres.
# Permet de supporter la double sortie sans perturber le parsing standard.
$DualOutput = $false
$rawArgs    = $MyInvocation.UnboundArguments
$cleanArgs  = @()

foreach ($a in $rawArgs) {
    if ($a -eq "-2") {
        $DualOutput = $true
    } else {
        $cleanArgs += $a
    }
}

# Paramètres principaux du script : validation, correction, mode silencieux, sortie fichier.
# Toute nouvelle option doit s’intégrer ici pour rester cohérente avec le reste du flux.
& {
param(
    [Alias("f")][Parameter(Position=0)][string]$File,
    [Alias("v")][switch]$Validate,
    [Alias("q")][switch]$Quiet,
    [Alias("c")][switch]$Correct,
    [Alias("s")][Parameter(Position=999)][string]$OutFile
)

# -------------------------------------------------
# FLAGS / MODE PARSING
# -------------------------------------------------

# Default = validate
if (-not $Validate -and -not $Correct) {
    $Validate = $true
}

# -v and -c cannot be used together
if ($Validate -and $Correct) {
    Write-Host "ERREUR: -v et -c ne peuvent pas être utilisés ensemble."
    exit 1
}

# -q seul => validation silencieuse
if ($Quiet -and -not ($Validate -or $Correct)) {
    $Validate = $true
}

# -------------------------------------------------
# FICHIER XML
# -------------------------------------------------

# Chargement du fichier XML contenant tous les paramètres attendus.
# Le XML est la source de vérité pour la comparaison, rien ne doit être codé en dur ailleurs.

if (-not $File) {
    Write-Host "ERREUR: paramètre obligatoire manquant: -f <fichier XML>."
    exit 1
}

if (-not ([System.IO.Path]::IsPathRooted($File))) {
    $ResolvedFile = Join-Path $RealScriptDir $File
} else {
    $ResolvedFile = $File
}

if (-not (Test-Path $ResolvedFile)) {
    Write-Host "ERREUR: fichier XML introuvable: $ResolvedFile"
    exit 1
}

# -------------------------------------------------
# SORTIE (TERMINAL / FICHIER / -2)
# -------------------------------------------------

# Gestion des modes de sortie : terminal, fichier ou les deux.
# Le but est d’unifier les sorties quel que soit le mode choisi.

$UserProvided_s = $PSBoundParameters.ContainsKey("OutFile")

if ($DualOutput -and -not $UserProvided_s) {
    Write-Host "ERREUR: -2 requiert l'utilisation de -s <fichier>."
    exit 1
}

$OutputToTerminal = $true
$OutputToFile     = $false
$ResolvedOutFile  = $null

if ($UserProvided_s) {
    if ([string]::IsNullOrWhiteSpace($OutFile)) {
        Write-Host "ERREUR: -s requiert un nom de fichier."
        exit 1
    }
    if ($OutFile.StartsWith("-")) {
        Write-Host "ERREUR: nom de fichier invalide pour -s: $OutFile"
        exit 1
    }

    try {
        $dir = Split-Path -Path $OutFile -Parent
        if ([string]::IsNullOrWhiteSpace($dir)) {
            $dir = "."
        }
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $OutFile)) {
            New-Item -Path $OutFile -ItemType File -Force | Out-Null
        }
        $ResolvedOutFile = (Resolve-Path $OutFile).Path
    }
    catch {
        Write-Host "ERREUR: impossible de créer ou d'accéder au fichier: $OutFile"
        exit 1
    }

    if ($DualOutput) {
        $OutputToTerminal = $true
        $OutputToFile     = $true
    } else {
        $OutputToTerminal = $false
        $OutputToFile     = $true
    }
}

# -------------------------------------------------
# CHARGEMENT XML
# -------------------------------------------------

try {
    $Xml = New-Object System.Xml.XmlDocument
    $Xml.Load($ResolvedFile)
}
catch {
    Write-Host "ERREUR: format XML invalide: $($_.Exception.Message)"
    exit 1
}

$ExpectedParameters = @()

foreach ($p in $Xml.Configuration.Parameter) {
    $ExpectedParameters += [PSCustomObject]@{
        Code        = [string]$p.Code
        Title       = [string]$p.Title
        ValueType   = [string]$p.ValueType
        ExpectedXml = $p.Expected
    }
}

if (-not $ExpectedParameters -or $ExpectedParameters.Count -eq 0) {
    Write-Host "ERREUR: aucun noeud <Parameter> trouvé dans le XML."
    exit 1
}

# -------------------------------------------------
# HELPERS: COLLECTEUR DE SORTIE
# -------------------------------------------------

# Collecteur de sortie. Toutes les lignes passent par ici avant l'affichage final.
# Facilite le support de la sortie unique ou double.

$OutputList = New-Object System.Collections.Generic.List[string]

function Add-Line {
    param([string]$Text)
    $OutputList.Add($Text)
}

# -------------------------------------------------
# HELPERS: PARSING net accounts (FR-FR)
# -------------------------------------------------

$script:NetAccountsInfo = $null

# Analyse la sortie FR de "net accounts" et retourne les valeurs de politique locales.
# Les variations FR-FR exigent plusieurs regex, d’où l’approche flexible.
function Get-NetAccountsInfo {
    if ($script:NetAccountsInfo) {
        return $script:NetAccountsInfo
    }

    $text = net accounts | Out-String
    $info = @{}

    if ($text -match "Nombre de mots de passe antérieurs à conserver\s*:\s*(.+)") {
        $raw = $matches[1].Trim()
        if ($raw -match "\d+") {
            $info["PasswordHistory"] = [int]($raw -replace "[^\d]", "")
        } elseif ($raw -match "Aucune") {
            $info["PasswordHistory"] = 0
        }
    }

    if ($text -match "Durée de vie maximale du mot de passe\s*\(jours\)\s*:\s*(\d+)") {
        $info["MaxAge"] = [int]$matches[1]
    }

    if ($text -match "Durée de vie minimale du mot de passe\s*\(jours\)\s*:\s*(\d+)") {
        $info["MinAge"] = [int]$matches[1]
    }

    if ($text -match "Longueur minimale du mot de passe\s*:\s*(\d+)") {
        $info["MinLength"] = [int]$matches[1]
    }

    if ($text -match "Seuil de verrouillage\s*:\s*(\d+)") {
        $info["LockoutThreshold"] = [int]$matches[1]
    }

    if ($text -match "Durée du verrouillage\s*\(min\)\s*:\s*(\d+)") {
        $info["LockoutDuration"] = [int]$matches[1]
    }

    # FIX: Try multiple French variations for lockout window
    if ($text -match "Fenêtre d'observation du verrouillage\s*\(min\)\s*:\s*(\d+)") {
        $info["LockoutWindow"] = [int]$matches[1]
    }
    elseif ($text -match "Fenêtre d'observation de verrouillage\s*\(min\)\s*:\s*(\d+)") {
        $info["LockoutWindow"] = [int]$matches[1]
    }
    elseif ($text -match "Observation du verrouillage\s*\(min\)\s*:\s*(\d+)") {
        $info["LockoutWindow"] = [int]$matches[1]
    }
    elseif ($text -match "Réinitialiser.*verrouillage.*\(min\)\s*:\s*(\d+)") {
        $info["LockoutWindow"] = [int]$matches[1]
    }

    $script:NetAccountsInfo = $info
    return $info
}

# -------------------------------------------------
# HELPERS: AUDITPOL (FR-FR → "Success,Failure")
# -------------------------------------------------

# Récupère l’état d’un sous-paramètre auditpol. Le format étant instable,
# la fonction s’appuie sur une regex robuste pour extraire Success/Failure.
function Get-AuditSetting {
    param([string]$SubcategoryFr)

    # Map subcategories to their parent categories
    $categoryMap = @{
        "Validation des informations d'identification" = "Connexion de compte"
        "Gestion des comptes d'utilisateur" = "Gestion des comptes"
        "Verrouillage du compte" = "Ouverture/Fermeture de session"
        "Ouvrir la session" = "Ouverture/Fermeture de session"
    }

    if (-not $categoryMap.ContainsKey($SubcategoryFr)) {
        return $null
    }

    $category = $categoryMap[$SubcategoryFr]

    try {
        # Get the entire category and parse for the specific subcategory
        $text = auditpol /get /category:"$category" 2>&1 | Out-String
    }
    catch {
        return $null
    }

    if (-not $text -or [string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    if ($text -match "Paramètre incorrect" -or $text -match "incorrect parameter") {
        return $null
    }

    # Parse the output to find the specific subcategory line
    # Format: "  Subcategory Name                      Setting"
    # Note: Sometimes there's no space between name and setting!
    $lines = $text -split "`r?`n"
    
    foreach ($line in $lines) {
        # Check if this line contains our subcategory
        # Match with optional spaces between subcategory and setting
        if ($line -match "^\s*$([regex]::Escape($SubcategoryFr))\s*(.+)$") {
            $setting = $matches[1].Trim()
            
            # Check for "Pas d'audit" / "No Auditing"
            if ($setting -match "Pas d'audit" -or $setting -match "No Auditing" -or $setting -match "Aucun audit") {
                return ""
            }
            
            # Parse "Succès et échec" / "Success and Failure" / "Succès" / "Échec" / "Réussite"
            $hasSuccess = $setting -match "Succès" -or $setting -match "Success" -or $setting -match "Réussite"
            $hasFailure = $setting -match "Échec" -or $setting -match "Failure"
            
            $vals = @()
            if ($hasSuccess) { $vals += "Success" }
            if ($hasFailure) { $vals += "Failure" }
            
            if ($vals.Count -eq 0) {
                return ""
            }
            
            return ($vals -join ",")
        }
    }

    return $null
}

# -------------------------------------------------
# HELPERS: VALEURS COURANTES (OS RÉEL)
# -------------------------------------------------

# Retourne la valeur réelle associée à un paramètre CIS donné.
# Chaque case du switch doit correspondre exactement à un paramètre du XML.
function Get-CurrentValue {
    param([string]$Title)

    switch ($Title) {

        "Enforce password history" {
            $info = Get-NetAccountsInfo
            if ($info.ContainsKey("PasswordHistory")) { return $info["PasswordHistory"] }
            return $null
        }

        "Maximum password age" {
            $info = Get-NetAccountsInfo
            if ($info.ContainsKey("MaxAge")) { return $info["MaxAge"] }
            return $null
        }

        "Minimum password age" {
            $info = Get-NetAccountsInfo
            if ($info.ContainsKey("MinAge")) { return $info["MinAge"] }
            return $null
        }

        "Minimum password length" {
            $info = Get-NetAccountsInfo
            if ($info.ContainsKey("MinLength")) { return $info["MinLength"] }
            return $null
        }

        "Password must meet complexity requirements" {
            $lsa = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue
            if (-not $lsa) { return $null }
            $val = $lsa.PasswordComplexity
            if ($null -eq $val) { return "Disabled" }
            if ($val -eq 1) { return "Enabled" } else { return "Disabled" }
        }

        "Relax minimum password length limits" {
            $lsa = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue
            if (-not $lsa) { return $null }
            $val = $lsa.RelaxMinimumPasswordLengthLimits
            if ($null -eq $val) { return "Disabled" }
            if ($val -eq 1) { return "Enabled" } else { return "Disabled" }
        }

        "Store passwords using reversible encryption" {
            $lsa = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue
            if (-not $lsa) { return $null }
            $val = $lsa.ClearTextPassword
            if ($null -eq $val) { return "Disabled" }
            if ($val -eq 1) { return "Enabled" } else { return "Disabled" }
        }

        "Account lockout duration" {
            $info = Get-NetAccountsInfo
            if ($info.ContainsKey("LockoutDuration")) { return $info["LockoutDuration"] }
            return $null
        }

        "Account lockout threshold" {
            $info = Get-NetAccountsInfo
            if ($info.ContainsKey("LockoutThreshold")) { return $info["LockoutThreshold"] }
            return $null
        }

        "Reset account lockout counter after" {
            $info = Get-NetAccountsInfo
            if ($info.ContainsKey("LockoutWindow")) { return $info["LockoutWindow"] }
            return $null
        }

        "Accounts: Guest account status" {
            $acc = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
            if (-not $acc) {
                $acc = Get-LocalUser -Name "Invité" -ErrorAction SilentlyContinue
            }
            if (-not $acc) { return $null }
            if ($acc.Enabled) { return "Enabled" } else { return "Disabled" }
        }

        "Limit blank passwords to console logon only" {
            $lsa = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue
            if (-not $lsa) { return $null }
            $val = $lsa.LimitBlankPasswordUse
            if ($null -eq $val) { return "Enabled" }
            if ($val -eq 1) { return "Enabled" } else { return "Disabled" }
        }

        "Microsoft FTP Service (FTPSVC)" {
            $svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
            if (-not $svc) { return "NotInstalled" }
            if ($svc.Status -eq "Running") {
                return "Enabled"
            } else {
                return "Disabled"
            }
        }

        "Windows Firewall: Domain: Firewall state" {
            $fw = Get-NetFirewallProfile -Profile Domain -ErrorAction SilentlyContinue
            if (-not $fw) { return $null }
            if ($fw.Enabled) { return "On" } else { return "Off" }
        }

        "Windows Firewall: Private: Firewall state" {
            $fw = Get-NetFirewallProfile -Profile Private -ErrorAction SilentlyContinue
            if (-not $fw) { return $null }
            if ($fw.Enabled) { return "On" } else { return "Off" }
        }

        "Windows Firewall: Public: Firewall state" {
            $fw = Get-NetFirewallProfile -Profile Public -ErrorAction SilentlyContinue
            if (-not $fw) { return $null }
            if ($fw.Enabled) { return "On" } else { return "Off" }
        }

        "Audit Credential Validation" {
            $result = Get-AuditSetting "Validation des informations d'identification"
            return $result
        }

        "Audit User Account Management" {
            $result = Get-AuditSetting "Gestion des comptes d'utilisateur"
            return $result
        }

        "Audit Account Lockout" {
            $result = Get-AuditSetting "Verrouillage du compte"
            return $result
        }

        "Audit Logon" {
            $result = Get-AuditSetting "Ouvrir la session"
            return $result
        }

        default {
            return $null
        }
    }
}

# -------------------------------------------------
# HELPERS: FORMATTAGE DES VALEURS ATTENDUES
# -------------------------------------------------

# Produit un résumé lisible de la valeur attendue (Minimum, Range, Enum, Multi).

function Get-ExpectedSummary {
    param(
        [System.Xml.XmlElement]$ExpectedNode,
        [string]$ValueType
    )

    if (-not $ExpectedNode) { return "" }

    switch ($ValueType) {

        "Minimum" {
            $min = [int]$ExpectedNode.Minimum
            return ">= $min"
        }

        "Range" {
            $start = [int]$ExpectedNode.Start
            $end   = [int]$ExpectedNode.End
            return "$start-$end"
        }

        "Enum" {
            return [string]$ExpectedNode.Value
        }

        "Multi" {
            $vals = @()
            foreach ($v in $ExpectedNode.Value) {
                $vals += [string]$v
            }
            return ($vals -join ",")
        }

        default {
            return ""
        }
    }
}

# -------------------------------------------------
# HELPERS: COMPARAISON COURANT / ATTENDU
# -------------------------------------------------

# Compare la valeur réelle à la valeur attendue selon le type défini dans le XML.
# Le comportement doit rester strict pour garantir la conformité CIS.

function Test-Compliance {
    param(
        [Parameter(Mandatory=$true)]$Current,
        [Parameter(Mandatory=$true)][System.Xml.XmlElement]$ExpectedNode,
        [Parameter(Mandatory=$true)][string]$ValueType
    )

    if ($null -eq $Current -or ([string]::IsNullOrWhiteSpace($Current.ToString()))) {
        return $false
    }

    switch ($ValueType) {

        "Minimum" {
            $min    = [int]$ExpectedNode.Minimum
            $curInt = [int]$Current
            return ($curInt -ge $min)
        }

        "Range" {
            $start  = [int]$ExpectedNode.Start
            $end    = [int]$ExpectedNode.End
            $curInt = [int]$Current
            return ($curInt -ge $start -and $curInt -le $end)
        }

        "Enum" {
            $expectedVal = [string]$ExpectedNode.Value
            return ($Current.ToString() -eq $expectedVal)
        }

        "Multi" {
            $op = $ExpectedNode.GetAttribute("operator")
            if ([string]::IsNullOrWhiteSpace($op)) {
                $op = "AND"
            }

            $expectedVals = @()
            foreach ($v in $ExpectedNode.Value) {
                $expectedVals += [string]$v
            }

            $currentVals = $Current.ToString().Split(",") |
                           ForEach-Object { $_.Trim() }

            if ($op -eq "OR") {
                foreach ($val in $expectedVals) {
                    if ($currentVals -contains $val) {
                        return $true
                    }
                }
                return $false
            } else {
                foreach ($val in $expectedVals) {
                    if (-not ($currentVals -contains $val)) {
                        return $false
                    }
                }
                return $true
            }
        }

        default {
            return $false
        }
    }
}

# -------------------------------------------------
# HELPERS: CORRECTION DES VALEURS NON CONFORMES
# -------------------------------------------------

# Applique la correction pour un paramètre non conforme.
# Chaque cas utilise l’outil approprié (secedit, registre, auditpol, services).
# Toute modification doit respecter l'approche CIS prévue pour ce paramètre.

function Set-CorrectValue {
    param(
        [string]$Title,
        [string]$ValueType,
        [System.Xml.XmlElement]$ExpectedNode
    )

    switch ($Title) {

        # 1.1.x – Password policies (via secedit)
        "Enforce password history" {
            $min = [int]$ExpectedNode.Minimum
$inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
PasswordHistorySize = $min
"@
            $path = "$env:TEMP\cis.inf"
            $inf | Set-Content $path -Encoding Unicode
            secedit /configure /db "$env:TEMP\cis.sdb" /cfg $path /areas SECURITYPOLICY /quiet | Out-Null
            return
        }

        "Maximum password age" {
            # For Range type, use Start as the target value (minimum in the range)
            $start = [int]$ExpectedNode.Start
            $end = [int]$ExpectedNode.End
            # If range allows flexibility, use a middle value, otherwise use Start
            $targetValue = if ($end - $start -gt 30) { 
                [math]::Min($start + 60, $end)  # Use Start+60 or End, whichever is smaller
            } else { 
                $start 
            }
$inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MaximumPasswordAge = $targetValue
"@
            $path = "$env:TEMP\cis.inf"
            $inf | Set-Content $path -Encoding Unicode
            secedit /configure /db "$env:TEMP\cis.sdb" /cfg $path /areas SECURITYPOLICY /quiet | Out-Null
            return
        }

        "Minimum password age" {
            $min = [int]$ExpectedNode.Minimum
$inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MinimumPasswordAge = $min
"@
            $path = "$env:TEMP\cis.inf"
            $inf | Set-Content $path -Encoding Unicode
            secedit /configure /db "$env:TEMP\cis.sdb" /cfg $path /areas SECURITYPOLICY /quiet | Out-Null
            return
        }

        "Minimum password length" {
            $min = [int]$ExpectedNode.Minimum
$inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MinimumPasswordLength = $min
"@
            $path = "$env:TEMP\cis.inf"
            $inf | Set-Content $path -Encoding Unicode
            secedit /configure /db "$env:TEMP\cis.sdb" /cfg $path /areas SECURITYPOLICY /quiet | Out-Null
            return
        }

        # 1.1.5 / 1.1.6 / 1.1.7 – LSA registry
        "Password must meet complexity requirements" {
            $want = [string]$ExpectedNode.Value
            $val = ($want -eq "Enabled") ? 1 : 0
            Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name PasswordComplexity -Value $val -Force
            return
        }

        "Relax minimum password length limits" {
            $want = [string]$ExpectedNode.Value
            $val = ($want -eq "Enabled") ? 1 : 0
            Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name RelaxMinimumPasswordLengthLimits -Value $val -Force
            return
        }

        "Store passwords using reversible encryption" {
            $want = [string]$ExpectedNode.Value
            $val = ($want -eq "Enabled") ? 1 : 0
            Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name ClearTextPassword -Value $val -Force
            return
        }

        # 1.2.x – Lockout policies (via secedit)
        "Account lockout duration" {
            $min = [int]$ExpectedNode.Minimum
$inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
LockoutDuration = $min
"@
            $path = "$env:TEMP\cis.inf"
            $inf | Set-Content $path -Encoding Unicode
            secedit /configure /db "$env:TEMP\cis.sdb" /cfg $path /areas SECURITYPOLICY /quiet | Out-Null
            return
        }

        "Account lockout threshold" {
            # FIX: Windows requires all three lockout settings to be set together
            # Get the expected value
            $end = [int]$ExpectedNode.End
            
            # We need to also set duration and window to satisfy Windows dependencies
            # Read current duration and window values
            $info = Get-NetAccountsInfo
            $duration = 15  # Default minimum from CIS
            $window = 15    # Default minimum from CIS
            
            if ($info.ContainsKey("LockoutDuration") -and $info["LockoutDuration"] -ge 15) {
                $duration = $info["LockoutDuration"]
            }
            if ($info.ContainsKey("LockoutWindow") -and $info["LockoutWindow"] -ge 15) {
                $window = $info["LockoutWindow"]
            }
            
$inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
LockoutBadCount = $end
LockoutDuration = $duration
ResetLockoutCount = $window
"@
            $path = "$env:TEMP\cis.inf"
            $inf | Set-Content $path -Encoding Unicode
            secedit /configure /db "$env:TEMP\cis.sdb" /cfg $path /areas SECURITYPOLICY /quiet | Out-Null
            
            # Give Windows a moment to apply the changes
            Start-Sleep -Milliseconds 500
            return
        }

        "Reset account lockout counter after" {
            $min = [int]$ExpectedNode.Minimum
$inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
ResetLockoutCount = $min
"@
            $path = "$env:TEMP\cis.inf"
            $inf | Set-Content $path -Encoding Unicode
            secedit /configure /db "$env:TEMP\cis.sdb" /cfg $path /areas SECURITYPOLICY /quiet | Out-Null
            return
        }

        # 2.3.1.x – Local accounts
        "Accounts: Guest account status" {
            $want   = [string]$ExpectedNode.Value
            $enable = ($want -eq "Enabled")

            $acc = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
            if (-not $acc) {
                $acc = Get-LocalUser -Name "Invité" -ErrorAction SilentlyContinue
            }
            if (-not $acc) { return }

            if ($enable) {
                Enable-LocalUser -Name $acc.Name
            } else {
                Disable-LocalUser -Name $acc.Name
            }
            return
        }

        "Limit blank passwords to console logon only" {
            $want = [string]$ExpectedNode.Value
            $val = ($want -eq "Enabled") ? 1 : 0
            Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LimitBlankPasswordUse -Value $val -Force
            return
        }

        # 5.11 – FTP service
        "Microsoft FTP Service (FTPSVC)" {
            $svc = Get-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
            if (-not $svc) {
                # NotInstalled → déjà conforme si le XML autorise NotInstalled
                return
            }

            # CIS: Disabled ou NotInstalled -> on désactive si présent
            Set-Service -Name "FTPSVC" -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name "FTPSVC" -ErrorAction SilentlyContinue
            return
        }

        # 9.x.x – Windows Firewall profiles (GpoBoolean)
        "Windows Firewall: Domain: Firewall state" {
            $want = [string]$ExpectedNode.Value
            $enabledEnum = if ($want -eq "On") {
                [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]::True
            } else {
                [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]::False
            }

            Set-NetFirewallProfile -Profile Domain -Enabled $enabledEnum
            return
        }

        "Windows Firewall: Private: Firewall state" {
            $want = [string]$ExpectedNode.Value
            $enabledEnum = if ($want -eq "On") {
                [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]::True
            } else {
                [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]::False
            }

            Set-NetFirewallProfile -Profile Private -Enabled $enabledEnum
            return
        }

        "Windows Firewall: Public: Firewall state" {
            $want = [string]$ExpectedNode.Value
            $enabledEnum = if ($want -eq "On") {
                [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]::True
            } else {
                [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]::False
            }

            Set-NetFirewallProfile -Profile Public -Enabled $enabledEnum
            return
        }

        # 17.x.x – Auditpol
        "Audit Credential Validation" {
            # Try both French and English subcategory names
            $result1 = auditpol /set /subcategory:"Validation des informations d'identification" /success:enable /failure:enable 2>&1
            if ($result1 -match "incorrect" -or $result1 -match "Paramètre incorrect") {
                auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable | Out-Null
            }
            return
        }

        "Audit User Account Management" {
            $result1 = auditpol /set /subcategory:"Gestion des comptes d'utilisateur" /success:enable /failure:enable 2>&1
            if ($result1 -match "incorrect" -or $result1 -match "Paramètre incorrect") {
                auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable | Out-Null
            }
            return
        }

        "Audit Account Lockout" {
            # Check if we need Success, Failure, or both
            $op = $ExpectedNode.GetAttribute("operator")
            $expectedVals = @()
            foreach ($v in $ExpectedNode.Value) {
                $expectedVals += [string]$v
            }
            
            $needsSuccess = $expectedVals -contains "Success"
            $needsFailure = $expectedVals -contains "Failure"
            
            # Build the auditpol command based on what's needed
            $successFlag = if ($needsSuccess) { "enable" } else { "disable" }
            $failureFlag = if ($needsFailure) { "enable" } else { "disable" }
            
            $result1 = auditpol /set /subcategory:"Verrouillage du compte" /success:$successFlag /failure:$failureFlag 2>&1
            if ($result1 -match "incorrect" -or $result1 -match "Paramètre incorrect") {
                auditpol /set /subcategory:"Account Lockout" /success:$successFlag /failure:$failureFlag | Out-Null
            }
            return
        }

        "Audit Logon" {
            $result1 = auditpol /set /subcategory:"Ouvrir la session" /success:enable /failure:enable 2>&1
            if ($result1 -match "incorrect" -or $result1 -match "Paramètre incorrect") {
                auditpol /set /subcategory:"Logon" /success:enable /failure:enable | Out-Null
            }
            return
        }

        default { return }
    }
}

# -------------------------------------------------
# MAIN LOOP
# -------------------------------------------------

Add-Line "---------- RESULTS ----------"

# Pour chaque paramètre du XML : récupération de la valeur réelle,
# comparaison, puis validation ou correction selon le mode actif.

foreach ($param in $ExpectedParameters) {

    $code      = $param.Code
    $title     = $param.Title
    $valueType = $param.ValueType
    $expNode   = $param.ExpectedXml

    $expectedSummary = Get-ExpectedSummary -ExpectedNode $expNode -ValueType $valueType
    $current         = Get-CurrentValue -Title $title

    if ($null -eq $current -or ([string]::IsNullOrWhiteSpace($current.ToString()))) {
        if ($Validate) {
            Add-Line "[$code] $title : valeur actuelle introuvable (attendu: $expectedSummary)"
        }
        continue
    }

    $ok = Test-Compliance -Current $current -ExpectedNode $expNode -ValueType $valueType

    # --------- MODE CORRECTION (-c) ----------
    if ($Correct) {
        if (-not $ok) {
            # Appliquer la correction
            Set-CorrectValue -Title $title -ValueType $valueType -ExpectedNode $expNode

            # Clear cached net accounts info so we re-read it
            $script:NetAccountsInfo = $null

            # Relire la valeur après correction pour vérifier
            $newCurrent = Get-CurrentValue -Title $title
            $okAfter    = $false
            if ($null -ne $newCurrent -and -not [string]::IsNullOrWhiteSpace($newCurrent.ToString())) {
                $okAfter = Test-Compliance -Current $newCurrent -ExpectedNode $expNode -ValueType $valueType
            }

            if ($okAfter) {
                Add-Line "[$code] $title : corrigé (nouvelle valeur: $newCurrent, attendu: $expectedSummary)"
            } else {
                Add-Line "[$code] $title : tentative de correction échouée (valeur actuelle: $newCurrent, attendu: $expectedSummary)"
            }
        } else {
            Add-Line "[$code] $title : déjà conforme ($current)"
        }

        # En mode -c, on ne repasse pas dans la logique -v
        continue
    }

    # --------- MODE VALIDATION (-v) ----------
    if ($Validate -and -not $Quiet) {
        if ($ok) {
            Add-Line "[$code] $title = $current (conforme)"
        } else {
            Add-Line "[$code] $title = $current (non conforme, attendu: $expectedSummary)"
        }
    }
    elseif ($Validate -and $Quiet) {
        if (-not $ok) {
            Add-Line "[$code] $title (non conforme, attendu: $expectedSummary)"
        }
    }
}

Add-Line "---------- END RESULTS ----------"

# -------------------------------------------------
# SORTIE FINALE
# -------------------------------------------------

# Prépare et écrit la sortie finale selon le mode choisi.
# L’ordre terminal → fichier (si dual) est intentionnel pour rester lisible.

if ($OutputToFile -and $ResolvedOutFile) {
    $OutputList | Out-File -FilePath $ResolvedOutFile -Encoding utf8 -Append
}

if ($OutputToTerminal) {
    $OutputList | Write-Output
}

exit 0

} @cleanArgs