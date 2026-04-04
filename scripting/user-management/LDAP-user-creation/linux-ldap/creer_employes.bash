#!/bin/bash
#Pour commencer, j'initialise les listes de mots et de symboles dont j'ai besoin pour créer les mots de passe aléatoires pour les utilisateurs.
mots=("Soleil" "Fraise" "Crayon")
symbols=("!" "$" "?")

#Je précise ici les variables que je vais utiliser tout au long du script afin de faciliter leur modification et leur utilisation. Les commandes LDAP sont trop longues!  
ldap_usr="cn=admin,dc=example,dc=com"
motdp=<your-ldap-admin-password>
ou_usr="ou=users,dc=example,dc=com"
ou_gr="ou=groups,dc=example,dc=com"
type_usr="(objectClass=posixAccount)"
type_inet="(objectClass=inetOrgPerson)"
type_org="(objectClass=organizationalPerson)"
type_shadow="(objectClass=shadowAccount)"
type_gr="(objectClass=posixGroup)"

#Fonction qui vérifie l'existence d'un groupe.
ver_gr(){
#J'utilise la commande sed pour me débarrasser des espaces qui peuvent être présents après et avant la variable de groupe.
	groupe=$(echo "$groupe" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
#Je stocke la commande ldapsearch dans la variable test_gr afin de pouvoir utiliser awk sur la ligne suivante pour extraire le cn exact, puis le comparer à la variable de groupe pour voir s'il existe déjà.
	test_gr=$(ldapsearch -x -LLL -D "$ldap_usr" -w $motdp -b "$ou_gr" "(&(objectClass=posixGroup)(cn=$groupe))")
	cn_gr=$(echo "$test_gr" | awk '/^cn:/ {print $2}')
#Après avoir comparé le cn extrait avec le nom du groupe, je stocke un 0 ou un 1 dans la variable ldap_gr_status que j'utiliserai dans la fonction cre_gr pour déterminer si un groupe doit être créé ou non.
	if [ "$cn_gr" != "$groupe" ]; then
		ldap_gr_status=1
	elif [ "$cn_gr" == "$groupe" ]; then
		ldap_gr_status=0
	fi
}

#Fonction qui créé un groupe.
cre_gr(){                                                                                                    
#J'utilise la fonction ver_gr pour voir si un groupe existe ou non avant de procéder.    
	ver_gr 
#Je stocke le résultat d'une commande shuf qui choisit aléatoirement un nombre entre 1000 et 9999 pour être utilisé plus tard pour créer le giduid du groupe.
	gidnb=$(shuf -i 1000-9999 -n 1)
	if [[ $ldap_gr_status -eq 1 ]]; then
#Je crée un groupe en utilisant l'option -f qui est généralement utilisée pour spécifier des fichiers en parallèle avec l'option echo -e qui contient toutes les informations de groupe pertinentes nécessaires pour créer un nouveau groupe.
		ldapadd -x -D "$ldap_usr" -w $motdp -f <(echo -e "dn: cn=$groupe,$ou_gr
		objectClass: posixGroup
		cn: $groupe
		gidNumber: $gidnb")
		echo "Création du groupe (LDAP): $groupe"
		return 100
	else
		echo "Le groupe $groupe existe déjà sur LDAP!"
		return 99
	fi

}

#Fonction qui vérifie l'existence d'un utilisateur. 
ver_usr(){
#J'utilise la commande sed pour me débarrasser des espaces qui peuvent être présents après et avant la variable du nom d'utilisateur. 
	username=$(echo "$username" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
#Je stocke la commande ldapsearch dans la variable test_usr afin de pouvoir utiliser awk sur la ligne suivante pour extraire le cn exact, puis le comparer à la variable du nom d'utilisateur pour voir s'il existe déjà.   	
	test_usr=$(ldapsearch -x -LLL -D "$ldap_usr" -w $motdp -b "$ou_usr" "(&(cn=$username)(|$type_usr$type_inet$type_org$type_shadow))")
	cn_usr=$(echo "$test_usr" | awk '/^cn:/ {print $2}')
#Après avoir comparé le cn extrait avec le nom d'utilisateur, je stocke un 1 ou un 2 dans la variable ldap_usr_status que j'utiliserai dans la fonction cre_usr pour déterminer si un utilisateur portant un nom d'utilisateur spécifique doit être créé.
	if [ "$cn_usr" == "$username" ]; then
		ldap_usr_status=1
	elif [ "$cn_usr" != "$username" ] && [ -n $cn_usr ]; then
		ldap_usr_status=2
	fi
}

#Fonction qui créé un utilisateur.    
cre_usr(){
#J'utilise la fonction ver_usr pour voir si un utilisateur portant un nom d'utilisateur spécifique existe ou non avant de procéder.   
	ver_usr
#J'utilise une boucle while pour comparer en continu le nom d'utilisateur avec les utilisateurs LDAP existants jusqu'à ce que le nom d'utilisateur généré soit différent de ceux de LDAP ou que le prénom de l'utilisateur que j'essaie de créer soit à court de lettres (épuisement de toutes les possibilités).
	while [[ $ldap_usr_status -ne 2 ]]; do
		if [ $debut_lettre -lt ${#prenom} ]; then
			username="${prenom:0:$((debut_lettre + 1))}${nom}"
			echo "Tentative de création de compte avec la combinaison de $prenom $nom; $username"
			ver_usr
		else
			echo "Impossible de créer un utilisateur avec la combinaison $prenom $nom; $username"
			return
		fi
		((debut_lettre++))
	done
#Cette instruction if sert à créer un répertoire local pour chaque utilisateur s'il n'existe pas déjà.
	if [ ! -d /home/$username ]; then
		mkdir /home/$username
	fi
#J'utilise la commande shuf pour générer aléatoirement un nombre compris entre 10 000 et 19 999 afin de créer des identifiants uniques pour chaque utilisateur (gidnumber).
	uid=$(shuf -i 10000-19999 -n 1)
#Comme précédemment dans le script, j'utilise l'option -f combinée à echo -e pour transmettre les spécifications souhaitées à la commande ldappadd.
#Pour créer un utilisateur, j'utilise les classes d'objets top, posixAccount, inetOrgPerson et shadowAccount afin de spécifier toutes les informations nécessaires à la création d'un nouvel utilisateur conforme aux exigences. Par exemple, shadowAccount est utilisé pour l'expiration du compte.
	ldapadd -x -D "$ldap_usr" -w $motdp -f <(echo -e "dn: cn=$username,$ou_usr
	objectClass: top
	objectClass: posixAccount
	objectClass: inetOrgPerson
	objectClass: shadowAccount
	givenName: $prenom
	sn: $nom
	cn: $username
	uid: $username
	uidNumber: $uid
	gidNumber: $gidnb
	homeDirectory: /home/$username
	employeeNumber: $no_emp
	displayName: "$prenom,$nom"
	description: $dept
	shadowExpire: $date_fin
	shadowLastChange: 0")
#J'ai utilisé la commande ldappasswd pour imposer le mot de passe temporaire créé sur chaque utilisateur.
	ldappasswd -x -D "$ldap_usr" -w $motdp -s $pass "cn=$username,$ou_usr"
#J'ai utilisé la commande ldapmodify pour ajouter des utilisateurs à leur groupe correspondant (j'ai utilisé l'option -f et echo -e).
	ldapmodify -x -D "$ldap_usr" -w $motdp -f <(echo -e "dn: cn=$groupe,$ou_gr
	changetype: modify
	add: memberUid
	memberUid: $username")
	echo "L'utilisateur $username ayant le mot de passe $pass a été créé!"
}

#J'utilise une instruction if pour vérifier si l'entrée provient d'une pipe, sinon elle n'exécute pas le reste du script.
if [ ! -t 0 ]; then
	input=$(cat)
	nb=0
#J'ai décidé d'utiliser une boucle while, mais, comme la première ligne était l'en-tête, j'ai démarré un compteur qui ignore la première itération de la boucle.
#La boucle a pour tâche principale de parcourir chaque utilisateur un par un.
#J'utilise la commande IFS pour diviser tous les champs du fichier csv afin de faciliter l'extraction de toutes les variables.
	while IFS=";" read -r system prenom nom no_emp dept date_fin groupe; do
		if [ $nb -eq 0 ]; then
                        ((nb++))
                        continue
                fi
#J'utilise la commande "RANDOM" pour générer un numéro d'index dans chacune des deux listes au début du script, puis je concatène le tout avec les 3 derniers chiffres du numéro d'employé pour créer un mot de passe temporaire.
		pass="${mots[$(( RANDOM % ${#mots[@]}))]}${symbols[$(( RANDOM % ${#symbols[@]}))]}${no_emp:(-3):3}"
#J'utilise la commande translate pour transformer toutes les lettres majuscules en minuscules du prénom et du nom de l'utilisateur.
		prenom=$(echo "$prenom" | tr '[:upper:]' '[:lower:]')
		nom=$(echo "$nom" | tr '[:upper:]' '[:lower:]')
		username="${prenom:0:1}${nom}"
#J'ai également ajouté une date d'expiration très lointaine pour les utilisateurs qui n'avaient pas le champ d'expiration du contrat (date_fin).
		if [ -n "$date_fin" ]; then
			date_fin=$(date -d "$date_fin" +%s)
		elif [ -z "$date_fin" ]; then
			date_fin="253402300799"
		fi
		debut_lettre=1
#J'utilise une instruction case pour vérifier à quel système appartient chaque utilisateur. Si l'utilisateur est dans AD ou Local-AD, il est créé dans LDAP avec son groupe et tout le reste. En revanche, s'il est dans Local, l'itération de la boucle est ignorée. Et, si le système n'est pas un des trois, la boucle passe à une nouvelle itération.
		case $system in
			AD)
				cre_gr
				cre_usr
				;;
			Local)
				continue	
				;;
			Local-AD)
				cre_gr
			      	cre_usr	
				;;
			*)
				echo "Type de système inconnu: $system"
				continue
		esac
	done <<< "$input"
else
	echo "L'entrée doit provenir d'une pipe!"
	exit 1

fi
