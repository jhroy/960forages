#!/usr/bin/env ruby
# ©2014 Jean-Hugues Roy. GNU GPL v3.

# Ce script extrait des données du Système d'information géoscientifique pétrolier et gazier (SIGPEG) du ministère de l'Énergie et des Ressources naturelles du Québec
# Il s'agit de données sur tous les puits forés au Québec depuis 1860 pour exploration ou exploitation de gaz naturel ou de pétrole

require "csv"
require "nokogiri"
require "open-uri"
require "watir-webdriver"

tout = [] # Création d'une matrice pour accueillir la totalité des résultats
fichier = "sigpeg.csv" # Déclaration du nom du fichier dans lequel seront écrit nos résultats
url1 = "http://geoegl.msp.gouv.qc.ca/Services/glo/V5/gloServeurHTTP.php?type=gps&cle=public&texte=GPS%20"
url2 = "&epsg=4326&format=xml"

 # Fonction pour convertir des coordonnées en degrés, minutes, secondes en coordonnées décimales

def latLong(coord)
	 return (coord[0..1].to_f + (coord[4..5].to_f/60) + ((coord[8..9].to_f) + (coord[11].to_f/10))/3600).round(6)
end

# Fonction pour convertir, au besoin, des pieds en mètres

def metres(pi)

	# Conditions qui vérifient tous les cas rencontrés dans la base de données du ministère
	
	if pi == "n.d."
		return pi
	elsif pi == "pi/sol"
		return "n.d."
	elsif pi == "pi/mer"
		return "n.d."
	elsif pi == "m/---"
		return "n.d."
	elsif pi[pi.index(" ")+1] == "p"
		m = pi[0..pi.index(" ")].to_i * 0.3048
		return m.round(2)
	else
		m = pi[0..pi.index(" ")].to_i
		return m.round(2)
	end
end

# Utilisation de watir-webdriver pour simuler une connexion au SIGPEG et différentes actions sur le site
# Cette simulation est la seule façon de faire afficher les pages où se trouvent les données à extraire

# On commence par ouvrir la page d'accueil du SIGPEG

sigpegAccueil = Watir::Browser.new
sigpegAccueil.goto "http://sigpeg.mrn.gouv.qc.ca/gpg/classes/rechercheIGPG?url_retour="

# Parfois, la page est en anglais. La condition ci-dessous vérifie si c'est le cas et si oui, clique sur le bouton «français»

if sigpegAccueil.title.include? "Oil"
	sigpegAccueil.image(:src, "../images/piv_tete/francais_a.gif").click
end

# Deuxième étape: on clique sur le bouton «Puits forés»

sigpegAccueil.image(:src, "../images/piv_menu/puits_fores.gif").click

# Troisième étape: on traite la page qui s'ouvre alors (celle des puits forés) avec Nokogiri

sigpeg = Nokogiri::HTML(sigpegAccueil.html)

# Quatrième étape: on extrait la liste de tous les numéros de puits du SIGPEG

listePuits = sigpeg.css("select")[2].css("option").map {|puits| puits["value"]}

# Cinquième étape: on passe toute la liste, un puits à la fois

listePuits.each do |noPuits|

	# On se sert de watir pour choisir le numéro de puits dans un menu déroulant

	sigpegAccueil.select_list(:name => "ARG").select noPuits

	# Quand le numéro de puits est sélectionné, on clique sur le bouton «Ajouter»

	sigpegAccueil.image(:src, "../images/recherche/ajouter.gif").click

	# On clique maintenant sur le nom du puits, ce qui déclenche un script en JavaScript qui fait apparaître («popup») une nouvelle fenêtre avec la fiche d'information sur le puits correspondant

	sigpegAccueil.execute_script('ouvrir("ficheDescriptive?mode=fichePuits&menu=puit&table=GPG_ENTRE_PUITS&cle=' + noPuits + '","Fiche","875","650");')
	
	# On se sert de la méthode «use» de watir pour dire qu'on va maintenant travailler sur la fenêtre popup qui vient d'ouvrir et dont le titre est «Fiche descriptive»

	sigpegAccueil.window(:title, "Fiche descriptive").use do

		# On traite la fenêtre qui ouvre avec Nokogiri

		fiche = Nokogiri::HTML(sigpegAccueil.html)

		# Création d'un hash pour inscrire les données de chaque puits

		donneesPuits = {}
		donneesPuits["Numéro du puits"] = noPuits
		donneesPuits["Nom du puits"] = fiche.css("h2")[0].text.strip

		# La section «Identification» de chaque fiche de puits est un tableau avec 26 lignes
		# On crée donc une boucle qui fera 26 fois la même extraction

		for i in 0..25 do

			titre = fiche.css("h5")[i].text.strip
			contenu = fiche.css("p")[i+1].text.strip.gsub(/\u00A0/, "") # Regex en unicode pour retrancher des espaces insécables
			donneesPuits[titre[1..-3]] = contenu

			# On effectue immédiatement certains calculs avec certaines données

			case i

			# Aux lignes 8 et 9, on transforme les coordonnées en degrés, minutes, secondes en coordonnées décimales à l'aide de la fonction «latLong» créée à cet effet

			when 7
				titre = "Latitude (décimal)"
				lat = latLong(contenu)
				donneesPuits[titre] = lat
			when 8
				titre = "Longitude (décimal)"
				long = latLong(contenu) * -1
				donneesPuits[titre] = long

			# Aux lignes 12, 13 et 14, on transforme en mètres, au besoin, des données en pieds à l'aide de la fonction «metres» créée à cette fin

			when 11
				titre = "Profondeur (en m)"			
				donneesPuits[titre] = metres(contenu)
			when 12
				titre = "Élévation (en m)"			
				donneesPuits[titre] = metres(contenu)
			when 13
				titre = "Élévation de la table de rotation (en m)"			
				donneesPuits[titre] = metres(contenu)

			# On sépare ensuite le contenu de la ligne 17 en deux, au besoin

			when 16
				if contenu.include? "\\"
					titre = "État du puits"
					donneesPuits[titre] = contenu[0..(contenu.index("\\")-1)]
					titre2 = "Contenu du puits"
					donneesPuits[titre2] = contenu[contenu.index("\\")+1..-1]
				else
					donneesPuits["État du puits"] = contenu
					donneesPuits["Contenu du puits"] = ""
				end
			end

		end

		# On se sert enfin du service de géolocalisation [GLO] du ministère de la Sécurité publique (http://geoegl.msp.gouv.qc.ca/accueil/)
		# pour identifier dans quelles municipalité, région et localité se trouve chaque puits à l'aide des coordonnées décimales calculées plus haut

		url = url1 + long.to_s + "," + lat.to_s + url2

		requete = Nokogiri::XML(open(url))

		municipalite = requete.xpath("//municipalite").text
		localite = requete.xpath("//localite").text.strip

		espace = municipalite.index(" (")
		region = municipalite[espace+2..-2]
		municipalite = municipalite[0..espace].strip
		if municipalite == ""
			municipalite = "Fleuve Saint-Laurent"
		end
		
		donneesPuits["Municipalité"] = municipalite
		donneesPuits["Région administrative"] = region
		donneesPuits["Localité"] = localite

		# Affichage des données extraites pour vérification

		puts "------------------------------"
		puts donneesPuits
		puts noPuits + "(" + listePuits.index(noPuits).to_s + ") réussi"
		puts "------------------------------"

		# On ajoute le hash du puits où on est rendu à la matrice de tous les puits

		tout.push donneesPuits

		# Certains puits ont été forés à nouveau, ou "réentrés" dans la terminologie du ministère
		# La condition ci-dessous vérifie si c'est le cas du puits où on se trouve
		# Si oui, il procède à l'extraction des données d'une nouvelle fenêtre surgissante dont la structure est légèrement différente (22 lignes au lieu de 26)

		if fiche.at_css("td.entete2 a")
			noPuitsReentre = noPuits + "-R1"
			sigpegAccueil.execute_script('ouvrir("ficheDescriptive?type=popup&mode=ficheReent&cle=' + noPuitsReentre + '&cleReentre=' + noPuitsReentre + '&menu=puit&ong_active=ongl_descriptive","FicheReentre","850","650");')
			sigpegAccueil.window(:index, 3).use do

				fiche = Nokogiri::HTML(sigpegAccueil.html)
				donneesPuits = {}
				donneesPuits["Numéro du puits"] = noPuitsReentre
				donneesPuits["Nom du puits"] = fiche.css("h2")[0].text.strip
				
				for i in 0..21 do

					titre = fiche.css("h5")[i].text.strip
					contenu = fiche.css("p")[i].text.strip.gsub(/\u00A0/, "") #regex en unicode pour retrancher des espaces insécables
					donneesPuits[titre[1..-3]] = contenu
					case i

					# Ajout de quatre éléments manquants dans la fiche du puits réentré en allant les chercher dans le dernier puits extrait

					when 1
						titre1 = "Lot"
						donneesPuits[titre1] = tout.last[titre1]
						titre2 = "Rang"
						donneesPuits[titre2] = tout.last[titre2]
						titre3 = "Canton"
						donneesPuits[titre3] = tout.last[titre3]
						titre4 = "Paroisse"
						donneesPuits[titre4] = tout.last[titre4]
					when 3
						titre = "Latitude (décimal)"
						donneesPuits[titre] = latLong(contenu)
					when 4
						titre = "Longitude (décimal)"
						donneesPuits[titre] = latLong(contenu) * -1
					when 7
						titre = "Profondeur (en m)"			
						donneesPuits[titre] = metres(contenu)
					when 8
						titre = "Élévation (en m)"			
						donneesPuits[titre] = metres(contenu)
					when 9
						titre = "Élévation de la table de rotation (en m)"			
						donneesPuits[titre] = metres(contenu)
					when 12
						if contenu.include? "\\"
							titre1 = "État du puits"
							donneesPuits[titre1] = contenu[0..(contenu.index("\\")-1)]
							titre2 = "Contenu du puits"
							donneesPuits[titre2] = contenu[contenu.index("\\")+1..-1]
						else
							donneesPuits["État du puits"] = contenu
							donneesPuits["Contenu du puits"] = ""
						end
					end

				end

				url = url1 + long.to_s + "," + lat.to_s + url2

				requete = Nokogiri::XML(open(url))

				municipalite = requete.xpath("//municipalite").text
				localite = requete.xpath("//localite").text.strip

				espace = municipalite.index(" (")
				region = municipalite[espace+2..-2]
				municipalite = municipalite[0..espace].strip
				if municipalite == ""
					municipalite = "Fleuve Saint-Laurent"
				end
				
				donneesPuits["Municipalité"] = municipalite
				donneesPuits["Région administrative"] = region
				donneesPuits["Localité"] = localite
		
				# Affichage des données extraites pour vérification

				puts donneesPuits
				puts noPuitsReentre + "(" + listePuits.index(noPuits).to_s + ") réussi"
				puts "----------"

				# On ajoute le hash du puits réentré à la matrice de tous les puits

				tout.push donneesPuits

			end

		end

	end

end

# Quand les données de tous les puits sont extraites, on les inscrit dans un fichier CSV

CSV.open(fichier, "wb") do |csv|
  csv << tout.first.keys
  tout.each do |hash|
    csv << hash.values
  end
end
