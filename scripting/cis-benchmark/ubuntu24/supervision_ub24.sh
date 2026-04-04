#!/bin/bash

# Ce script valide ou corrige des paramètres CIS à partir d'un XML.
# Il lit les valeurs réelles (dpkg, sysctl, systemctl, fichiers système),
# les compare aux attentes, puis applique ou affiche les corrections.
# Toute modification interne doit respecter la séquence XML -> valeurs réelles -> comparaison -> action.
# =====================================================================
# SCRIPT CIS - Ubuntu 24.04 LTS, STANDALONE (NON DOMAIN-JOINED)
# =====================================================================

# I got 96% for this exam, I honestly don't know what I missed, but I know I spent less time on this script than the windows one, so I guess that's my fault


# Détermine l'emplacement réel du script pour résoudre correctement les chemins relatifs vers le XML.
# Nécessaire si le script est lancé depuis un autre répertoire.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Extraction manuelle du flag -2 avant la gestion native des paramètres.
# Permet de supporter la double sortie sans perturber le parsing standard.
DUAL_OUTPUT=false
CLEAN_ARGS=()

for arg in "$@"; do
    if [[ "$arg" == "-2" ]]; then
        DUAL_OUTPUT=true
    else
        CLEAN_ARGS+=("$arg")
    fi
done
set -- "${CLEAN_ARGS[@]}"

# -------------------------------------------------
# FLAGS / MODE PARSING
# -------------------------------------------------

# Paramètres principaux du script : validation, correction, mode silencieux, sortie fichier.
# Toute nouvelle option doit s'intégrer ici pour rester cohérente avec le reste du flux.
FILE=""
VALIDATE=false
CORRECT=false
QUIET=false
OUTFILE=""
OUTFILE_PROVIDED=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            FILE="$2"
            shift 2
            ;;
        -v)
            VALIDATE=true
            shift
            ;;
        -c)
            CORRECT=true
            shift
            ;;
        -q)
            QUIET=true
            shift
            ;;
        -s)
            OUTFILE="$2"
            OUTFILE_PROVIDED=true
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Default = validate
if ! $VALIDATE && ! $CORRECT; then
    VALIDATE=true
fi

# -v et -c ne peuvent pas être utilisés ensemble
if $VALIDATE && $CORRECT; then
    echo "ERREUR: -v et -c sont incompatibles."
    exit 1
fi

# -q seul => validation silencieuse
if $QUIET && ! $VALIDATE && ! $CORRECT; then
    VALIDATE=true
fi

# -------------------------------------------------
# FICHIER XML
# -------------------------------------------------

# Chargement du fichier XML contenant tous les paramètres attendus.
# Le XML est la source de vérité pour la comparaison, rien ne doit être codé en dur ailleurs.
if [[ -z "$FILE" ]]; then
    echo "ERREUR: -f <file.xml> est requis."
    exit 1
fi

# -------------------------------------------------
# SORTIE (TERMINAL / FICHIER / -2)
# -------------------------------------------------

# Gestion des modes de sortie : terminal, fichier ou les deux.
# Le but est d'unifier les sorties quel que soit le mode choisi.
if $DUAL_OUTPUT && ! $OUTFILE_PROVIDED; then
    echo "ERREUR: -2 requiert -s <outfile>."
    exit 1
fi

OUTPUT_TO_TERMINAL=true
OUTPUT_TO_FILE=false

if $OUTFILE_PROVIDED; then
    if $DUAL_OUTPUT; then
        OUTPUT_TO_TERMINAL=true
        OUTPUT_TO_FILE=true
    else
        OUTPUT_TO_TERMINAL=false
        OUTPUT_TO_FILE=true
    fi
fi

if $OUTPUT_TO_FILE; then
    mkdir -p "$(dirname "$OUTFILE")"
    touch "$OUTFILE"
fi

# -------------------------------------------------
# CHARGEMENT XML
# -------------------------------------------------

if ! xmlstarlet sel -t -c "/" "$FILE" >/dev/null 2>&1; then
    echo "ERREUR: XML invalide."
    exit 1
fi

# -------------------------------------------------
# HELPERS: COLLECTEUR DE SORTIE
# -------------------------------------------------

# Collecteur de sortie. Toutes les lignes passent par ici avant l'affichage final.
# Facilite le support de la sortie unique ou double.
OUTPUT_LINES=()
add_line() { OUTPUT_LINES+=("$1"); }

# -------------------------------------------------
# HELPERS: LECTURE DES VALEURS CIBLES DEPUIS XML
# -------------------------------------------------

# Extrait la valeur cible depuis le XML pour un code CIS donné.
# Utilisé par les fonctions de correction pour savoir quelle valeur appliquer.
# Retourne la première valeur appropriée selon le type (Minimum, Range, Enum, Pattern, Multi).
get_xml_target_value() {
    local code="$1"
    local xpath="/Configuration/Parameter[Code='$code']/Expected"
    local valuetype=$(xmlstarlet sel -t -v "/Configuration/Parameter[Code='$code']/ValueType" "$FILE")
    
    case "$valuetype" in
        Minimum)
            xmlstarlet sel -t -v "$xpath/Minimum" "$FILE"
            ;;
        Range)
            xmlstarlet sel -t -v "$xpath/Start" "$FILE"
            ;;
        Enum|Pattern)
            xmlstarlet sel -t -v "$xpath/Value[1]" "$FILE"
            ;;
        Multi)
            xmlstarlet sel -t -m "$xpath/Value" -v "." -o "," "$FILE" | sed 's/,$//'
            ;;
    esac
}

# -------------------------------------------------
# HELPERS: CORRECTION DES VALEURS NON CONFORMES
# -------------------------------------------------

# Applique la correction pour un paramètre non conforme.
# Chaque cas utilise l'outil approprié (apt, sysctl, systemctl, sed, chmod).
# Toute modification doit respecter l'approche CIS prévue pour ce paramètre.

correct_224() {
    local target=$(get_xml_target_value "2.2.4")
    
    if [[ "$target" == "not-installed" ]]; then
        if dpkg -l telnet 2>/dev/null | grep -q '^ii'; then
            if sudo apt-get -y purge telnet >/dev/null 2>&1; then
                echo "telnet supprimé"
            else
                echo "échec suppression telnet"
            fi
        else
            echo "telnet déjà non installé"
        fi
    else
        if ! dpkg -l telnet 2>/dev/null | grep -q '^ii'; then
            if sudo apt-get -y install telnet >/dev/null 2>&1; then
                echo "telnet installé"
            else
                echo "échec installation telnet"
            fi
        else
            echo "telnet déjà installé"
        fi
    fi
}

correct_226() {
    local target=$(get_xml_target_value "2.2.6")
    
    if [[ "$target" == "not-installed" ]]; then
        if dpkg -l ftp 2>/dev/null | grep -q '^ii'; then
            if sudo apt-get -y purge ftp >/dev/null 2>&1; then
                echo "ftp supprimé"
            else
                echo "échec suppression ftp"
            fi
        else
            echo "ftp déjà non installé"
        fi
    else
        if ! dpkg -l ftp 2>/dev/null | grep -q '^ii'; then
            if sudo apt-get -y install ftp >/dev/null 2>&1; then
                echo "ftp installé"
            else
                echo "échec installation ftp"
            fi
        else
            echo "ftp déjà installé"
        fi
    fi
}

correct_331() {
    local target=$(get_xml_target_value "3.3.1")
    
    sudo sysctl -w net.ipv4.ip_forward="$target" >/dev/null 2>&1
    echo "net.ipv4.ip_forward = $target" | sudo tee /etc/sysctl.d/99-cis-ipv4.conf >/dev/null
    sudo sysctl -p /etc/sysctl.d/99-cis-ipv4.conf >/dev/null 2>&1
    echo "IP forwarding défini à $target"
}

correct_411() {
    echo "correction firewall non automatique (configurations multiples possibles)"
}

correct_421() {
    local target=$(get_xml_target_value "4.2.1")
    
    if [[ "$target" == "installed" ]]; then
        if ! dpkg -l ufw 2>/dev/null | grep -q '^ii'; then
            if sudo apt-get -y install ufw >/dev/null 2>&1; then
                echo "ufw installé"
            else
                echo "échec installation ufw"
            fi
        else
            echo "ufw déjà installé"
        fi
    else
        if dpkg -l ufw 2>/dev/null | grep -q '^ii'; then
            if sudo apt-get -y purge ufw >/dev/null 2>&1; then
                echo "ufw supprimé"
            else
                echo "échec suppression ufw"
            fi
        else
            echo "ufw déjà non installé"
        fi
    fi
}

correct_423() {
    local target=$(get_xml_target_value "4.2.3")
    
    if [[ "$target" == "enabled" ]]; then
        sudo systemctl enable ufw >/dev/null 2>&1 || true
        sudo ufw --force enable >/dev/null 2>&1 || true
        echo "ufw activé"
    else
        sudo systemctl disable ufw >/dev/null 2>&1 || true
        sudo ufw --force disable >/dev/null 2>&1 || true
        echo "ufw désactivé"
    fi
}

correct_5411() {
    local target=$(get_xml_target_value "5.4.1.1")
    
    if grep -qE '^PASS_MAX_DAYS' /etc/login.defs 2>/dev/null; then
        sudo sed -ri "s/^(PASS_MAX_DAYS\s+).*/\1$target/" /etc/login.defs
    else
        echo "PASS_MAX_DAYS $target" | sudo tee -a /etc/login.defs >/dev/null
    fi
    echo "PASS_MAX_DAYS défini à $target"
}

correct_5413() {
    local target=$(get_xml_target_value "5.4.1.3")
    
    if grep -qE '^PASS_WARN_AGE' /etc/login.defs 2>/dev/null; then
        sudo sed -ri "s/^(PASS_WARN_AGE\s+).*/\1$target/" /etc/login.defs
    else
        echo "PASS_WARN_AGE $target" | sudo tee -a /etc/login.defs >/dev/null
    fi
    echo "PASS_WARN_AGE défini à $target"
}

correct_5414() {
    local target=$(get_xml_target_value "5.4.1.4")
    
    if sudo grep -qE '^password\s+.*pam_unix.so' /etc/pam.d/common-password 2>/dev/null; then
        sudo sed -ri "/^password\s+.*pam_unix.so/ {
            s/(yescrypt|sha512|sha256|md5)//g
            s/pam_unix\.so\s+/pam_unix.so $target /
        }" /etc/pam.d/common-password
        echo "hachage défini à $target"
    else
        echo "ligne pam_unix.so introuvable"
    fi
}

correct_5415() {
    local target=$(get_xml_target_value "5.4.1.5")
    
    # Si target est "configured", on veut une valeur positive (30)
    # Si target est "not-configured", on veut -1
    local value=30
    if [[ "$target" == "not-configured" ]]; then
        value=-1
    fi
    
    # Regex stricte: ligne commencant par INACTIVE= (pas de # devant)
    # Remplace tout apres le = par la nouvelle valeur
    if sudo grep -q "^INACTIVE=" /etc/default/useradd 2>/dev/null; then
        sudo sed -ri "s/^INACTIVE=.*$/INACTIVE=$value/" /etc/default/useradd
    else
        echo "INACTIVE=$value" | sudo tee -a /etc/default/useradd >/dev/null
    fi
    echo "INACTIVE defini a $value"
}

correct_5416() {
    echo "correction dates passwords non automatique"
}

correct_5421() {
    echo "correction UID 0 non automatique"
}

correct_5422() {
    echo "correction GID 0 non automatique"
}

correct_5424() {
    local target=$(get_xml_target_value "5.4.2.4")
    
    if [[ "$target" == "L" ]] || [[ "$target" == "LK" ]]; then
        sudo passwd -l root >/dev/null 2>&1 || true
        echo "root verrouillé"
    else
        sudo passwd -u root >/dev/null 2>&1 || true
        echo "root déverrouillé"
    fi
}

correct_5427() {
    echo "correction shells système non automatique"
}

correct_5432() {
    local target=$(get_xml_target_value "5.4.3.2")
    local file="/etc/profile.d/cis_tmout.sh"

    sudo mkdir -p /etc/profile.d >/dev/null 2>&1 || true
    echo "TMOUT=$target" | sudo tee "$file" >/dev/null
    echo "readonly TMOUT" | sudo tee -a "$file" >/dev/null
    echo "export TMOUT" | sudo tee -a "$file" >/dev/null
    echo "TMOUT configuré à $target"
}

correct_6111() {
    echo "systemd-journald correction non nécessaire"
}

correct_6114() {
    local target=$(get_xml_target_value "6.1.1.4")
    
    if [[ "$target" == "journald" ]]; then
        if systemctl is-active rsyslog >/dev/null 2>&1; then
            sudo systemctl disable --now rsyslog >/dev/null 2>&1 || true
        fi
        if systemctl is-active syslog-ng >/dev/null 2>&1; then
            sudo systemctl disable --now syslog-ng >/dev/null 2>&1 || true
        fi
        echo "journald configuré comme unique système de logs"
    else
        echo "configuration logging multiple non automatique"
    fi
}

correct_711() {
    local target=$(get_xml_target_value "7.1.1")
    
    if sudo chmod "$target" /etc/passwd >/dev/null 2>&1; then
        echo "permissions /etc/passwd définies à $target"
    else
        echo "échec chmod /etc/passwd"
    fi
}

perform_correction() {
    local code="$1"

    case "$code" in
        "2.2.4")   correct_224 ;;
        "2.2.6")   correct_226 ;;
        "3.3.1")   correct_331 ;;
        "4.1.1")   correct_411 ;;
        "4.2.1")   correct_421 ;;
        "4.2.3")   correct_423 ;;
        "5.4.1.1") correct_5411 ;;
        "5.4.1.3") correct_5413 ;;
        "5.4.1.4") correct_5414 ;;
        "5.4.1.5") correct_5415 ;;
        "5.4.1.6") correct_5416 ;;
        "5.4.2.1") correct_5421 ;;
        "5.4.2.2") correct_5422 ;;
        "5.4.2.4") correct_5424 ;;
        "5.4.2.7") correct_5427 ;;
        "5.4.3.2") correct_5432 ;;
        "6.1.1.1") correct_6111 ;;
        "6.1.1.4") correct_6114 ;;
        "7.1.1")   correct_711 ;;
        *)
            echo "aucune correction automatique définie"
            ;;
    esac
}

# -------------------------------------------------
# HELPERS: VALEURS COURANTES (OS RÉEL)
# -------------------------------------------------

# Retourne la valeur réelle associée à un paramètre CIS donné.
# Chaque case du switch doit correspondre exactement à un paramètre du XML.
get_current_value() {
    local title="$1"

    case "$title" in

        "Ensure telnet client is not installed")
            dpkg -l telnet 2>/dev/null | grep -q '^ii' && echo "installed" || echo "not-installed"
            ;;

        "Ensure ftp client is not installed")
            dpkg -l ftp 2>/dev/null | grep -q '^ii' && echo "installed" || echo "not-installed"
            ;;

        "Ensure ip forwarding is disabled")
            local val=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
            echo "${val:-unknown}"
            ;;

        "Ensure a single firewall configuration utility is in use")
            local firewalls=()
            
            if command -v ufw &>/dev/null; then
                if sudo -n ufw status 2>/dev/null | grep -qi "Status: active"; then
                    firewalls+=("ufw:active")
                elif systemctl is-enabled ufw 2>/dev/null | grep -q "enabled"; then
                    firewalls+=("ufw:enabled")
                fi
            fi
            
            if command -v firewalld &>/dev/null; then
                if systemctl is-active firewalld 2>/dev/null | grep -q "active"; then
                    firewalls+=("firewalld:active")
                elif systemctl is-enabled firewalld 2>/dev/null | grep -q "enabled"; then
                    firewalls+=("firewalld:enabled")
                fi
            fi
            
            if [ ${#firewalls[@]} -eq 0 ]; then
                echo "none"
            elif [ ${#firewalls[@]} -eq 1 ]; then
                echo "${firewalls[0]}"
            else
                echo "multiple:${firewalls[*]}"
            fi
            ;;

        "Ensure ufw is installed")
            dpkg -l ufw 2>/dev/null | grep -q '^ii' && echo "installed" || echo "not-installed"
            ;;

        "Ensure ufw service is enabled")
            local status=$(systemctl is-enabled ufw 2>/dev/null)
            echo "${status:-disabled}"
            ;;

        "Ensure password expiration is configured")
            local days=$(grep -E '^PASS_MAX_DAYS' /etc/login.defs 2>/dev/null | awk '{print $2}')
            echo "${days:-not-set}"
            ;;

        "Ensure password expiration warning days is configured")
            local days=$(grep -E '^PASS_WARN_AGE' /etc/login.defs 2>/dev/null | awk '{print $2}')
            echo "${days:-not-set}"
            ;;

        "Ensure strong password hashing algorithm is configured")
            local algo=$(grep -E '^password.*pam_unix.so' /etc/pam.d/common-password 2>/dev/null \
                | grep -oE 'yescrypt|sha512|sha256|md5' | head -n1)
            echo "${algo:-none}"
            ;;

        "Ensure inactive password lock is configured")
            local inactive=$(sudo awk -F= '/^INACTIVE=/ {print $2}' /etc/default/useradd 2>/dev/null | tail -n1 | tr -d '[:space:]')
            if [[ -n "$inactive" ]] && [[ "$inactive" =~ ^[0-9]+$ ]] && [[ "$inactive" -gt 0 ]]; then
                echo "configured"
            else
                echo "not-configured"
            fi
            ;;

        "Ensure all users last password change date is in the past")
            local invalid_users=()
            while IFS=: read -r user pass lastchg rest; do
                if [[ $lastchg =~ ^[0-9]+$ ]] && [ "$lastchg" -gt 0 ]; then
                    local lastchg_epoch=$((lastchg * 86400))
                    local now_epoch=$(date +%s)
                    if [ "$lastchg_epoch" -gt "$now_epoch" ]; then
                        invalid_users+=("$user")
                    fi
                fi
            done < <(sudo awk -F: '($3>=1000 && $1!="nobody"){print}' /etc/shadow 2>/dev/null)
            
            if [ ${#invalid_users[@]} -eq 0 ]; then
                echo "all-valid"
            else
                echo "invalid-dates:${invalid_users[*]}"
            fi
            ;;

        "Ensure root is the only UID 0 account")
            awk -F: '($3==0){print $1}' /etc/passwd | paste -sd,
            ;;

        "Ensure root is the only GID 0 account")
            awk -F: '($4==0){print $1}' /etc/passwd | paste -sd,
            ;;

        "Ensure root account access is controlled")
            sudo passwd -S root 2>/dev/null | awk '{print $2}' || echo "unknown"
            ;;

        "Ensure system accounts do not have a valid login shell")
            local accounts=$(awk -F: '($3<1000 && $3!=0 && $1!="sync" && $1!="shutdown" && $1!="halt" && $7!~/nologin|false/){print $1":"$7}' /etc/passwd 2>/dev/null | paste -sd,)
            echo "${accounts:-none}"
            ;;

        "Ensure default user shell timeout is configured")
            local tmout=$(grep -R "^[[:space:]]*TMOUT=" /etc/profile /etc/bash.bashrc /etc/profile.d 2>/dev/null \
                | grep -v '#' | head -n1 | grep -oE '[0-9]+')
            echo "${tmout:-not-set}"
            ;;

        "Ensure journald service is enabled and active")
            local enabled=$(systemctl is-enabled systemd-journald.service 2>/dev/null)
            local active=$(systemctl is-active systemd-journald.service 2>/dev/null)
            echo "${enabled:-unknown},${active:-unknown}"
            ;;

        "Ensure only one logging system is in use")
            local systems=()
            
            if systemctl is-active rsyslog &>/dev/null | grep -q active; then
                systems+=("rsyslog")
            fi
            if systemctl is-active syslog-ng &>/dev/null | grep -q active; then
                systems+=("syslog-ng")
            fi
            
            systems+=("journald")
            
            if [ ${#systems[@]} -eq 1 ]; then
                echo "${systems[0]}"
            else
                echo "${systems[*]}"
            fi
            ;;

        "Ensure permissions on /etc/passwd are configured")
            stat -c %a /etc/passwd 2>/dev/null || echo "unknown"
            ;;

        *)
            echo "UNKNOWN"
            ;;
    esac
}

# -------------------------------------------------
# HELPERS: FORMATTAGE DES VALEURS ATTENDUES
# -------------------------------------------------

# Produit un résumé lisible de la valeur attendue (Minimum, Range, Enum, Multi, Pattern).
get_expected_summary() {
    local xpath="$1"
    local valuetype="$2"

    case "$valuetype" in
        Minimum)
            xmlstarlet sel -t -v "$xpath/Minimum" "$FILE"
            ;;
        Range)
            local s e
            s=$(xmlstarlet sel -t -v "$xpath/Start" "$FILE")
            e=$(xmlstarlet sel -t -v "$xpath/End" "$FILE")
            echo "${s}-${e}"
            ;;
        Enum)
            xmlstarlet sel -t -m "$xpath/Value" -v "." -o " or " "$FILE" | sed 's/ or $//'
            ;;
        Multi)
            xmlstarlet sel -t -m "$xpath/Value" -v "." -o " and " "$FILE" | sed 's/ and $//'
            ;;
        Pattern)
            xmlstarlet sel -t -m "$xpath/Value" -v "." -o " or " "$FILE" | sed 's/ or $//'
            ;;
    esac
}

# -------------------------------------------------
# HELPERS: COMPARAISON COURANT / ATTENDU
# -------------------------------------------------

# Compare la valeur réelle à la valeur attendue selon le type défini dans le XML.
# Le comportement doit rester strict pour garantir la conformité CIS.
test_compliance() {
    local current="$1"
    local param_xpath="$2"
    local valuetype="$3"
    local title="$4"

    case "$valuetype" in
        Minimum)
            local min
            min=$(xmlstarlet sel -t -v "$param_xpath/Expected/Minimum" "$FILE")
            if [[ "$current" =~ ^-?[0-9]+$ ]] && [[ "$min" =~ ^[0-9]+$ ]]; then
                [[ "$current" -ge "$min" ]]
                return
            fi
            return 1
            ;;
        Range)
            local s e
            s=$(xmlstarlet sel -t -v "$param_xpath/Expected/Start" "$FILE")
            e=$(xmlstarlet sel -t -v "$param_xpath/Expected/End" "$FILE")
            if [[ "$current" =~ ^[0-9]+$ ]]; then
                [[ "$current" -ge "$s" && "$current" -le "$e" ]]
                return
            fi
            return 1
            ;;
        Enum)
            local op
            op=$(xmlstarlet sel -t -v "$param_xpath/Expected/@operator" "$FILE")
            
            local exp_values=()
            while IFS= read -r val; do
                exp_values+=("$val")
            done < <(xmlstarlet sel -t -m "$param_xpath/Expected/Value" -v "." -n "$FILE")
            
            if [[ "$op" == "OR" ]]; then
                for exp in "${exp_values[@]}"; do
                    [[ "$current" == "$exp" ]] && return 0
                done
                return 1
            else
                [[ "$current" == "${exp_values[0]}" ]]
                return
            fi
            ;;
        Pattern)
            local op
            op=$(xmlstarlet sel -t -v "$param_xpath/Expected/@operator" "$FILE")
            
            local patterns=()
            while IFS= read -r val; do
                patterns+=("$val")
            done < <(xmlstarlet sel -t -m "$param_xpath/Expected/Value" -v "." -n "$FILE")
            
            if [[ "$op" == "OR" ]]; then
                for pattern in "${patterns[@]}"; do
                    [[ "$current" == "$pattern" ]] && return 0
                done
                return 1
            else
                for pattern in "${patterns[@]}"; do
                    [[ "$current" != "$pattern" ]] && return 1
                done
                return 0
            fi
            ;;
        Multi)
            local op
            op=$(xmlstarlet sel -t -v "$param_xpath/Expected/@operator" "$FILE")
            
            local exp_values=()
            while IFS= read -r val; do
                exp_values+=("$val")
            done < <(xmlstarlet sel -t -m "$param_xpath/Expected/Value" -v "." -n "$FILE")
            
            IFS=',' read -ra cur <<< "$current"

            if [[ "$op" == "OR" ]]; then
                for e in "${exp_values[@]}"; do
                    for c in "${cur[@]}"; do
                        [[ "$c" == "$e" ]] && return 0
                    done
                done
                return 1
            else
                for e in "${exp_values[@]}"; do
                    local found=false
                    for c in "${cur[@]}"; do
                        if [[ "$c" == "$e" ]]; then
                            found=true
                            break
                        fi
                    done
                    [[ "$found" == false ]] && return 1
                done
                return 0
            fi
            ;;
    esac

    return 1
}

# -------------------------------------------------
# MAIN LOOP
# -------------------------------------------------

add_line "---------- RESULTS ----------"

# Pour chaque paramètre du XML : récupération de la valeur réelle,
# comparaison, puis validation ou correction selon le mode actif.
param_count=$(xmlstarlet sel -t -v "count(/Configuration/Parameter)" "$FILE")

for i in $(seq 1 "$param_count"); do
    xpath="/Configuration/Parameter[$i]"

    code=$(xmlstarlet sel -t -v "$xpath/Code" "$FILE")
    title=$(xmlstarlet sel -t -v "$xpath/Title" "$FILE")
    valuetype=$(xmlstarlet sel -t -v "$xpath/ValueType" "$FILE")

    expected_summary=$(get_expected_summary "$xpath/Expected" "$valuetype")
    current=$(get_current_value "$title")

    ok=false
    if test_compliance "$current" "$xpath" "$valuetype" "$title"; then ok=true; fi

    # --------- MODE CORRECTION (-c) ----------
    if $CORRECT; then
        if ! $ok; then
            add_line "[$code] $title : correction en cours..."
            correction_msg=$(perform_correction "$code")
            add_line "  $correction_msg"
        else
            add_line "[$code] $title : déjà conforme ($current)"
        fi
        # En mode -c, on ne repasse pas dans la logique -v
        continue
    fi

    # --------- MODE VALIDATION (-v) ----------
    if $VALIDATE && ! $QUIET; then
        if $ok; then
            add_line "[$code] $title = $current (conforme)"
        else
            add_line "[$code] $title = $current (NON conforme, attendu: $expected_summary)"
        fi
    elif $VALIDATE && $QUIET; then
        ! $ok && add_line "[$code] $title (NON conforme)"
    fi
done

add_line "---------- END RESULTS ----------"

# -------------------------------------------------
# SORTIE FINALE
# -------------------------------------------------

# Prépare et écrit la sortie finale selon le mode choisi.
# L'ordre terminal → fichier (si dual) est intentionnel pour rester lisible.
if $OUTPUT_TO_TERMINAL; then
    for line in "${OUTPUT_LINES[@]}"; do echo "$line"; done
fi

if $OUTPUT_TO_FILE; then
    for line in "${OUTPUT_LINES[@]}"; do echo "$line" >> "$OUTFILE"; done
fi