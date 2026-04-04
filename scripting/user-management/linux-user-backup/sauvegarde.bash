#!/bin/bash
#Avant de démarrer la boucle principale, je définis les variables pour l’horodatage requis (année-mois-jour_heure_minutes_secondes) et pour le chemin du fichier .log.
horodatage=$(date +"%Y-%m-%d_%H_%M_%S")
dest_log="/tmp/sauvegarde/sauvegarde.$horodatage.log"
#Ensuite, j'ai ajouté une instruction if pour vérifier si le sous-répertoire /tmp/sauvegarde a été créé, sinon, le script le créera.
#Il est important de mentionner que le script journalise tous les évènements après cette partie dans le fichier .log.
if [ -d /tmp/sauvegarde/ ]; then
	echo "Début de la sauvegarde à $horodatage" > "$dest_log"
	echo "Début de la sauvegarde"
else
	echo "Création du répertoire de sauvegarde..."
	mkdir -p /tmp/sauvegarde/
	echo "Début de la sauvegarde à $horodatage" > "$dest_log"
	echo "Début de la sauvegarde"
fi
#Pour traiter chaque utilisateur individuellement, j'ai utilisé une boucle for, dans laquelle j'ai utilisé la commande cut pour sélectionner les noms d'utilisateur dans le premier champ de chaque utilisateur répertorié dans /etc/passwd.
for user in $(cut -d: -f1 /etc/passwd); do
	user_uid=$(getent passwd "$user" | cut -d: -f3)
#Ensuite, j'ai choisi de ne faire des sauvegardes que pour les utilisateurs ayant un UID supérieur à 1000, car sinon, cela sauvegarderait les utilisateurs du système, qui ont des milliers de fichiers, ce qui utiliserait toute la mémoire du serveur.
	if [[ $user_uid -ge 1000 ]]; then
		echo "Traitement de l'utilisateur: $user" >> "$dest_log"
		user_home=$(getent passwd "$user" | cut -d: -f6)
#Après avoir validé que l'utilisateur a un UID supérieur à 1000, le script utilise une boucle if pour vérifier si un utilisateur a un répertoire personnel et si c'est le cas, il démarrera l'archivage du répertoire personnel de l'utilisateur et de tous les sous-répertoires et fichiers.
		if [[ -d "$user_home" ]]; then
			sauvegarde="/tmp/sauvegarde/${user}_${horodatage}.tar.gz"
			tar -czvpf "$sauvegarde" --same-owner "$user_home" >> "$dest_log" 2>&1
#Enfin, avant de terminer un tas de conditions if et la boucle elle-même, je vérifie que le répertoire de l'utilisateur qui a été traité a été correctement sauvegardé avec une boucle if qui compare l'état de sortie de la dernière commande exécutée ($?).
			if [[ $? -eq 0 ]]; then
				echo "Sauvegarde réussie pour l'utilisateur: $user" >> "$dest_log"
			else
				echo "Sauvegarde non-réussie pour l'utilisateur: $user" >> "$dest_log"
			fi
		else
			echo "Cet utilisateur ne possède pas de répertoire: $user, sauvegarde non-éffectuée" >> "$dest_log"
		fi
	else
		echo "Utilisateur système ou sans répertoire valable: $user, sauvegarde ignorée" >> "$dest_log"
	fi
done
echo "Sauvegarde des répertoires des utilisateurs terminée" >> "$dest_log"
echo "Fin de la sauvegarde"
