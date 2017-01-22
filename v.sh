#!/usr/bin/env bash
# set -xv
set -o posix -ef #-o pipefail # ajouter l'option u ("unlinked") pour vérifier que les variables ne sont pas sans lien (désactivée ici : -u ne semble pas gérer correctement les variables awk $X)

name="$0"
version="$name version 2017.03 \"more params\""
c=1 # seuls les mots apparaissant au moins c fois seront conservés
L=42 # le nombre de mots utilisés pour détecter la langue d'entrée
T=3 # le nombre de mots utilisés pour deviner le thème d'un texte
w=1 # seuls les mots de w lettres et plus seront conservés
cwfp="$(dirname $0)/data/ls_common_4k/"
nature="not found"
theme="not found"


# flags correspondant aux arguments renseignés
c_on=false ; l_on=false ; L_on=false ; n_on=false ; p_on=false ; s_on=false ; t_on=false ; T_on=false ; w_on=false

manpage="NAME
		$name - a tool around text basic analysis

SYNOPSIS
		\033[1m$name\033[0m \033[4mFILE\033[0m [\033[1m-c\033[0m \033[4mMIN\033[0m] [\033[1m-l\033[0m] [\033[1m-L\033[0m \033[4mNUM\033[0m] [\033[1m-n\033[0m] [\033[1m-p\033[0m] [\033[1m-s\033[0m] [\033[1m-t\033[0m] [\033[1m-T\033[0m \033[4mNUM\033[0m] [\033[1m-w\033[0m \033[4mMIN\033[0m]
		\033[1m$name\033[0m [\033[1m--help\033[0m|\033[1m--manual\033[0m|\033[1m--version\033[0m]

DESCRIPTION
		Analyze a given text.

		-c, --counts
			the minimum counts requirement for words to be kept during analysis

		-l, --language
			prints the guessed input language

		-L
			the number of words kept during language detection

		-n, --nature
			try to guess the nature of text

		-p, --processing
			print processing output (default behaviour unless -l and/or -n are specified)

		-s, --stopwords
			enable stopword filtering (requires internet connection)

		-t, --theme
			try to guess the theme of the text

		-T
			the number of words kept during theme seeking
		
		-w, --word-length
			the minimum length requirement for words to be kept during analysis

		-h, --help
			show command synopsis

		--man, --manual
			show this manualpage

		--version
			output version information and exit

AUTHOR
		Written by Rémi Taunay.

REPORTING BUGS
		Do not report $name bugs.

COPYRIGHT
		This is free software: you are free to change and redistribute it. There is absolutely no warranty. Use $name at your own risk.

SEE ALSO
		The full documentation for $name is maintained here. Do not look for any external help or documentation. Hey, what did you expect?
"



# intervient lorsque l'appel est incorrect
function dispUsage {
	echo -e "\n\tUsage:\n$(echo "$manpage" | awk '/SYNOPSIS/,/DESCRIPTION/' | egrep -v 'SYNOPSIS|DESCRIPTION')\n"
}



# traite le texte
function performAnalysis {

	# vérification des paramètres
	valid

	# vérification de l'encodage
	#encodage="$(chardet < "$f" | sed 's#^.*: \(.*\) (.*$#\1#')"
	#if [ "$encodage" == 'None' ]; then
	#	echo -e '\033[31mEncodage non reconnu.\033[0m' >&2
	#	exit
	#fi
	encodage=$(file -b --mime-encoding $f)

	# conversion de l'entrée en UTF-8
	iconv -f "$encodage" -t 'UTF-8' < "$f"|\

	# passage en sauts de ligne en UNIX
	tr '\r' '\n'|\

	# on ne conserve que les mots
	tr '_' '\n' | sed 's#\W#\n#g'|\

	# on supprime les nombres se faisant passer pour des mots
	sed 's#[[:digit:]]##g'|\

	# on enlève les lignes vides
	sed '/^$/d'|\

	# on supprime la casse
	tr '[:upper:]' '[:lower:]'|\

	# on regroupe les différents exemplaires d'un même mot
	sort|\

	# que l'on garde en un exemplaire en dénombrant les occurrences
	uniq -c|\

	# on ne met qu'un seul espace en guise de marge (facultatif)
	sed 's#[[:blank:]]*\(.*\)#\1#g'|\

	# on trie selon le nombre d'occurrences
	sort -g|\

	# on supprime les mots dont le nombre d'occurrences est trop bas
	awk -v c="${c}" '{if($1>=c) print $0}'|\

	# on ajoute en début de ligne la longueur du mot, en filtrant les mots dont la longueur est trop faible
	awk -v w="${w}" '{l=length($2); if(l>=w) print l" "$0}'|\

	# on trie selon la longueur (à ce point, c'est trié des plus faibles fréquences vers les plus élevées)
	#sort -g|\

	# on retire la longueur
	awk '{print $2" "$3}'>tmp/vout_0.txt # tee posant problème (obligation de sleep à l'entrée de detectLanguage pour attendre l'écriture), passage par un bête fichier temporaire, sans tee

	# détection de la langue d'entrée
	detectLanguage
	lang=$(cat tmp/vlang.txt)

	# on filtre les stopwords
	cat tmp/vout_0.txt | filterStopwords >tmp/vout_00.txt # on garde le résultat du processing caché

	# on recherche la nature du texte
	getVerbs
	guessNature
	nature=$(cat tmp/vnature.txt)

	#on recherche le thème du texte
	guessTheme
	theme=$(cat tmp/vtheme.txt)

	show # affichage final
}



# se charge des affichages utilisateur
function show {
	# -p montre le résultat du filtrage à l'utilisateur si demandé
	if [ $l_on = false ] && [ $n_on = false ] && [ $t_on = false ]; then p_on=true ;fi # par défaut, pas d'affichage du processing si on cherche à connaître des carctéristiques précises du texte
	if [ $p_on = true ]; then cat tmp/vout_00.txt ;fi      # -p processing si demandé
	if ([ $l_on = true ] || [ $n_on = true ] || [ $t_on = true ]) && [ $p_on = true ]; then echo "======= Results =======" ;fi # affichage d'un séparateur entre la partie traitement et la partie infos, si besoin est
	if [ $l_on = true ]; then echo "language: ${lang}" ;fi # -l langue     si demandée
	if [ $n_on = true ]; then echo "nature: ${nature}" ;fi # -n nature     si demandée
	if [ $t_on = true ]; then echo "theme: ${theme}" ;fi   # -t thème      si demandé
}



# tente de deviner la nature d'un texte
function guessNature {
	if [ $n_on = true ]; then
		if [ "$lang" = "french" ]; then
			
			# contiennent une liste de textes relatifs aux formes de verbes trouvées
			narratif="conte, nouvelle, roman, reportage, fait divers, anecdote, fable"
			injonctif="recette, notice, consigne, mode d'emploi, didacticiel, règlement, loi"
			explicatif="encyclopédie, dictionnaire, documentaire, manuel, revue critique"

			ls -1 "data/nature/" | while read fichier_de_terminaison; do
				echo "$(grep -cf data/nature/$fichier_de_terminaison tmp/vverb.txt) $fichier_de_terminaison"
			done | sort -g | head -1 | awk '{print $2}' >tmp/vnature.txt

			# on donne la nature du texte et une liste des écrits possibles s'y rapportant
			case "$(cat tmp/vnature.txt)" in
				'narratif') echo "narratif : $narratif" >tmp/vnature.txt ;;
				'injonctif') echo "injonctif : $injonctif" >tmp/vnature.txt ;;
				'explicatif') echo "explicatif : $explicatif" >tmp/vnature.txt ;;
			esac
		else
			dispHasNoVerbsErr # non disponible pour cette langue
		fi
	fi
}




# tente de deviner le thème d'un texte
function guessTheme {
	if [ $t_on = true ]; then
		# filtrage des prénoms, qui viennent interférer avec la détection du thème
		awk '{print $2}' tmp/vout_00.txt >tmp/vout_00a.txt
		grep -xvFf data/prenoms/prenoms.txt tmp/vout_00a.txt >tmp/vout_00b.txt
		# on tente de trouver un thème commun aux 3 mots (hors prénoms) les plus utilisés
		regex="$(tail -$T tmp/vout_00b.txt | iconv -f utf8 -t ascii//TRANSLIT | awk '{print "(?=\\b"$2"\\b).*"}' ORS='' | sed 's#\.\*$##')" # il n'y a pas d'accents dans l'encyclopédie virtuelle   |   utilisation de PCRE (option -P) pour pouvoir utiliser les lookafters sur les mots-clés
		grep -qPim 1 "$regex" data/champ_lexi/ve.txt | tr '+-' ' ' | sed 's#^\(.*\):.*$#\1#' >tmp/vtheme.txt
		if [ -z "$(cat tmp/vtheme.txt)" ]; then tail -1 tmp/vout_00.txt | awk '{print $2}'>tmp/vtheme.txt ;fi # le mot ayant la + haute fréquence fera office de thème car matcher les 3 mots les + hauts en fréquence n'a pas abouti
	fi
}



# filtrer et compter dans un fichier séparé les verbes détectés si souhaité, lorsque la langue est fr
function getVerbs {
	if [ $n_on = true ]; then
		if [ "$lang" = "french" ]; then
			awk '{print $2}' tmp/vout_00.txt >tmp/vout_2.txt
			grep -wFf tmp/vout_2.txt data/verbs/french.txt >tmp/vverb.txt
		else
			dispHasNoVerbsErr # non disponible pour cette langue
		fi
	fi
}


# erreur : n'a pas la liste des verbes pour cette langue
function dispHasNoVerbsErr {
	echo -e "\033[31mNo verbs found for the ${lang} language.\033[0m" >&2
	exit
}



# détecte la langue d'entrée
function detectLanguage {
	tail -$L tmp/vout_0.txt | awk '{print $2}' >tmp/vout_1.txt
	echo "$(
	ls -1 "${cwfp}" | while read lang_file; do
		echo "$(grep -xcFf tmp/vout_1.txt "$cwfp/$lang_file") $(echo "$cwfp/$lang_file" | sed 's#^.*/\(\w*\).txt$#\1#g')"
	done | sort -g | tail -1 | awk '{print $2}'
	)" > tmp/vlang.txt
}




# vérifie l'existence d'un fichier
# précondition : $f existe
function checkFile {
	if [ ! -f "$f" ]; then
		echo -e "\033[31mCan't reach file \"$f\".\033[0m" >&2
		exit
	fi
}



# erreur : un paramètre a été donné en doublon
# précondition : $pgt existe
function dispParamGivenTwiceErr {
	echo -e "\033[31mSeveral \"-$pgt\" options were given, but only one is expected.\033[0m" >&2
	exit
}




# vérifie si les string données en paramètre sont des représentations valides d'entiers positifs non nuls
function valid {

	# pour savoir si un paramètre est ok
	c_ok=false
	w_ok=false

	# on matche ce qui correspond à des entiers
	r='^0*[1-9][0-9]*$'

	if [[ $c =~ $r ]]; then c_ok=true ;fi
	if [[ $w =~ $r ]]; then w_ok=true ;fi

	if [ $c_ok = false ]; then echo -e "\033[31mParameter \"-c\" must be given a natural number. Found : \"$c\"\033[0m" >&2 ;fi
	if [ $w_ok = false ]; then echo -e "\033[31mParameter \"-w\" must be given a natural number. Found : \"$w\"\033[0m" >&2 ;fi

	if [ $c_ok = false ] || [ $w_ok = false ]; then exit ;fi
}



# vérifie s'il est possible de récupérer les stopwords de la langue $lang
function hasLangStopwords {
	sw_lang_available="$(wget -qO- 'http://members.unine.ch/jacques.savoy/clef/' | grep '<a href="clef/.*ST.txt' | sed 's#^.*clef\/\(.*\)ST.txt.*$#\1#g' | tr '[:upper:]' '[:lower:]')"
	if [ "${sw_lang_available/$lang}" = "$sw_lang_available" ] ; then
	  echo false
	else
	  echo true
	fi
}



# récupère les stopwords d'une langue donnée dans $stop
# précondition : c'est possible, @see hasLangStopwords
function getStopwords {
	stop="$(wget -qO- "http://members.unine.ch/jacques.savoy/clef/${lang}ST.txt" | uniq | awk '{if(length($1)>=w) print $0}' | iconv -f 'WINDOWS-1252' -t 'UTF-8')"
	st_arr=($stop)
}



# notification : impossible de récupéer les stopwords pour cette langue
function dispHasNoStopwordsErr {
	echo -e "\033[31mNo stopwords found for the ${lang} language.\033[0m" >&2
}



# filtre stdin afin d'enlever les stopwords, si possible
function filterStopwords {
	if [ $s_on = true ]; then # on filtre
		if [ "$(hasLangStopwords)" = true ]; then
			
			getStopwords # récupération des stopwords
			est_st=false

			# $mot est le mot courant lu sur stdin : il provient du texte en input
			# i=${i//[[:space:]]} # équivaut à i=$(echo "$i" | sed 's/[[:space:]]//g'), mais étant bash natif, c'est de loin plus rapide
			
			while read -r line; do
				mmot="$(echo "$line" | awk '{print $0}')"
				mot="$(echo "$mmot" | awk '{print $2}')"
				mot="${mot%[[:space:]]}"
				est_st=false
				for i in "${st_arr[@]}"; do
					if [ "$mot" == "${i%[[:space:]]}" ]; then
						est_st=true
						break
					fi
				done
				if [ $est_st = false ]; then
					echo "$mmot"
				fi
			done

		else
			dispHasNoStopwordsErr # impossible de récupérer les stopwords
		fi
	else # on ne filtre pas
		cat # on répète donc simplement sur stdout
	fi
}



# @deprecated vérifie s'il est possible de récupérer les mots usuels de la langue $lang sur wiktionnaire
# function hasLangUsualwords {
# 	uw_lang_available="$(wget -qO- 'https://fr.wiktionary.org/wiki/Wiktionnaire:Listes_de_fr%C3%A9quence' | grep "toclevel-2.*f=\"[^_]*\"" | sed 's|^.*>\(\w*\)<\/span>.*$|\1|' | tr '[[:upper:]]' '[[:lower:]]')"
# 	if [ "${uw_lang_available/$lang}" = "$uw_lang_available" ] ; then
# 	  echo false
# 	else
# 	  echo true
# 	fi
# }



# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ début du script ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# traitement des arguments, on switch case sur leur nombre
case "$#" in
0)
	# appel à vide
	dispUsage
	exit
	;;
1)
	# gestion manuelle des paramètres d'aide
	case "$1" in
		'-h' | '--help') dispUsage;;
		'--man' | '--manual') echo -e "$manpage" | more;;
		'--version') echo "$version";;
		*)
			# l'unique paramètre est un fichier
			f="$1" ; shift
			checkFile

			# les valeur de c et w ont été assignées aux valeurs par défaut
			# on procède donc directement au traitement
			performAnalysis
			;;
	esac
	;;

*)
	# le premier paramètre est un fichier
	f="$1" ; shift
	checkFile

	# on remplace manuellement les paramètres longs par leurs équivalents courts et on condense les paramètres (suppression des éventuels espace de séparation)
	args="$(echo "$@" | sed 's|--counts|-c|g' | sed 's|--language|-l|g' | sed 's|--nature|-n|g' | sed 's|--processing|-p|g' | sed 's|--stopwords|-s|g' | sed 's|--theme|-t|g' | sed 's|--word-length|-w|g' | sed -r 's| +-([^ -]+) +([^ -]+)| -\1\2|g')"
	lsargs=($args) # on split sur IFS

	# on parse les arguments
	while getopts ':c:L:lnpstT:w:' flag "${lsargs[@]}"; do

		case "$flag" in
			c)
				if "$c_on"; then
					pgt='c'
					dispParamGivenTwiceErr
				fi
				c="$OPTARG" # @override default value
				c_on=true # filtrage selon le nombre d'occurences activé
				;;
			l)
				if "$l_on"; then
					pgt='l'
					dispParamGivenTwiceErr
				fi
				l_on=true # l'affichage de la langue du texte devinée est souhaitée
				;;
			L)
				if "$L_on"; then
					pgt='L'
					dispParamGivenTwiceErr
				fi
				L="$OPTARG" # @override default value
				L_on=true # souhaite préciser le nombre de mots à utiliser pour la détection de la langue
				;;
			n)
				if "$n_on"; then
					pgt='n'
					dispParamGivenTwiceErr
				fi
				n_on=true # nature du texte ?
				;;
			p)
				if "$p_on"; then
					pgt='p'
					dispParamGivenTwiceErr
				fi
				p_on=true # montrer le résultat du processing (mots ayant passé les filtres + fréquences)
				;;
			s)
				if "$s_on"; then
					pgt='s'
					dispParamGivenTwiceErr
				fi
				s_on=true # filtrage des stopwords souhaité
				;;
			t)
				if "$t_on"; then
					pgt='t'
					dispParamGivenTwiceErr
				fi
				t_on=true # thème du texte ?
				;;
			T)
				if "$T_on"; then
					pgt='T'
					dispParamGivenTwiceErr
				fi
				T="$OPTARG" # @override default value
				T_on=true # souhaite préciser le nombre de mots à utiliser pour deviner le thème
				;;
			w)
				if "$w_on"; then
					pgt='w'
					dispParamGivenTwiceErr
				fi
				w="$OPTARG" # @override default value
				w_on=true # filtrage selon la longueur des mots souhaitée
				;;
			:)
				echo -e "\033[31mOption \"-$OPTARG\" requires an argument.\033[0m" >&2
				exit
				;;
			\?)
				echo -e "\033[31mUnexpected argument \"-$OPTARG\".\033[0m" >&2
				dispUsage
				exit
				;;
		esac
	done

	# la gestion des paramètres est (enfin!) terminée, on passe donc la main à performAnalysis
	performAnalysis
	;;
esac


# ===================================== bloc notes =====================================

# [STOCK] ne concerne qu'une langue (fr), parsage spécifique à ces pages
# deprecated_usual_fr=`wget -qO- 'http://eduscol.education.fr/cid47916/liste-des-mots-classee-par-frequence-decroissante.html' | egrep '[[:alpha:]]+</td>' | sed 's#^.*>\(.*\)<.*$#\1#g' | recode html..utf8 | sort | uniq`
# deprecated_stop_fr=`wget -qO- 'http://www.ranks.nl/stopwords/french' | awk '/<tr>/,/<\/tr>/' | tr -d '[:space:]' | sed 's#<[^<]*>#\d10#g' | sed '/^$/d'| recode html..utf8 | sort`

# engin de recherche badass : dtsearch
# on peut dire que les 1000 premiers mots (en fréquence) d'un texte (après élagage des stopwords) contiennent le sens d'un texte
# les textes fournis en entrée doivent correspondre au texte brut, sans en-têtes, préfaces, license, table des matières...
# set -xv pour débogguer
# shellcheck permet d'améliorer la qualité du code
# pour améliorer la conformité du script aux normes POSIX par soucis de compatibilité, il est possible de changer le comportement de bash afin que celui-ci colle davantage aux normes POSIX
# lorsque filtrage par -w et -s actif, on filtre -s en conséquence. en effet il est inutile de filtrer selon des stopwords plus petits que tous les mots à filtrer : il n'y aura aucun match c'est donc un ralentissemnt inutile
# les boucles sont EXTRÊMEMENT lentes en bash
# récupérer les 4000 mots les + utilisés de chaque langue : wget -r --no-parent -A '4000[a-z][a-z].txt' http://plouffe.fr/IUT/Modelisation%20maths/liste4000motslesplusutilises/
# pour debug (attendre l'appui sur une touche pour continuer) : read -n1 -r -p "Press any key to continue..." key
# pour modifier le comportement par défaut du script, modifier les valeurs booléennes des flags. ATTENTION: le comportement peut être indéterminé et être source de crashs de la part du script
# en bash, une fonction peu difficilement renvoyer une valeur à l'appelant. 2 solutions : le code de retour [0;255], ou l'écriture dans un fichier relu par le parent (c'est ce qui se passe ici avec la langue détectée)
# l'intérêt de vider le dossier tmp au sein du script est restreint puisque les fichiers s'y trouvant se font override à chaque lancement de toute manière
# liste de prénoms récupérée ici (licence GNU) : http://www.lexique.org/public/prenoms.php qui permet de ne pas cherche un thème contenant ces prénoms

# perspectives d'amélioration :
# * utilisation d'égrappoirs (cf http://members.unine.ch/jacques.savoy/clef/frenchStemmerPlus.txt pour du Français par exemple) lors de certains traitements
# * "nettoyer" l'encyclopédie virtuelle (redondance, formatage, accentuation)
