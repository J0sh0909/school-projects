#!/bin/bash
#Tout d'abord, puisque les instructions précisent que le script doit être exécuté dans une pipe, je vérifie avec une instruction « if » s'il est exécuté de cette façon, sinon il quitte avec le statut 1.
if [ ! -t 0 ]; then
#J'utilise la variable « input » pour stocker tout le contenu à partir de la pipe à l'aide de la commande « cat », provenant du fichier des utilisateurs.
	input=$(cat)
#Cette boucle est essentiellement divisée en 3 parties. 
#La première partie lit l'entrée, sépare chaque ligne en fonction des espaces ou des tabulations en deux variables nom et prénom, transforme la chaîne en minuscules, puis concatène ces deux variables en une seule et initialise également le compteur pour la deuxième partie de la boucle while. 
	while IFS= read -r utilisateur; do
		IFS=$' \t' read -r prenom nom <<< "$utilisateur"
		prenom=$(echo "$prenom" | tr '[:upper:]' '[:lower:]')
		nom=$(echo "$nom" | tr '[:upper:]' '[:lower:]')
		debut_lettre=1
		username="${prenom:0:1}${nom}"
#La deuxième partie de la boucle principale est une autre boucle while qui est chargée de générer un nom d'utilisateur unique pour chaque utilisateur dans la boucle while principale.
#Plus précisément, la deuxième boucle utilise le nom d'utilisateur créé à l'étape précédente pour vérifier s'il existe déjà et utilise &>/dev/null pour rediriger les deux sorties (stdout et stderr) vers /dev/null (un trou noir) afin de ne pas encombrer le terminal de messages.
		while id "$username" &>/dev/null; do
#Ensuite, le script lance une instruction if pour s'assurer que le compteur (debut_lettre) ne dépasse pas le nombre de lettres du prénom, sinon, il quitte avec le statut 2. 
			if [ $debut_lettre -lt ${#prenom} ]; then
				username="${prenom:0:$((debut_lettre + 1))}${nom}"
				echo "Tentative de création de compte avec la combinaison de $prenom $nom; $username"
			else
				echo "Impossible de créer un utilisateur avec la combinaison $prenom $nom; $username"
				exit 2
			fi
#Dans cette deuxième étape de la boucle, le compteur augmente de 1 à chaque fois jusqu'à ce qu'un nom unique soit créé ou que le prénom n'ait plus de lettres.
			((debut_lettre++))
		done
#La troisième partie de la boucle crée un utilisateur basé sur la partie précédente, utilise le $? pour vérifier le dernier état de sortie de la commande de création d'utilisateur et le compare à 0 pour voir s'il a été correctement exécuté.
#Essentiellement, il vérifie si la création de l'utilisateur a été correctement effectuée, sinon il quitte avec le statut 3, et si le mot de passe a été attribué avec succès, sinon il quitte avec le statut 4.
		useradd -m "$username"
		if [ $? -ne 0 ]; then
			echo "Erreur lors de la création de l'utilisateur $username"
			exit 3
		fi
		echo "$username:<your-default-password>" | chpasswd
		if [ $? -ne 0 ]; then
			echo "Erreur lors de l'attribution du mot de passe à l'utilisateur $username"
			exit 4
		fi
		echo "Création de l'utilisateur $prenom $nom; $username"
#Il est précisé que la boucle principale doit utiliser le contenu de la variable « input » située au début du script.
	done <<< "$input"
else
    echo "L'entrée doit provenir d'une pipe!"
    exit 1
fi
