# DE10-NANO-Wav-Player
-------------------------------------------------------------------------------------------------------

Je partage le code source d'un Wave Player que j'ai eu plaisir à coder sur une carte FPGA DE10-NANO.
Il s'agit d'un lecteur de musique au format WAVE. Le programme affiche une liste de fichiers wav sur un écran avec un haut-parleur intégré (un écran de télé fait l'affaire). Et le tout est controlé par une manette de jeu connectée en filaire sur un des ports USB d'une carte d'extension que j'ai ajouté à ma carte DE1-Nano.

J'ai réalisé ce projet en auto-didact car je n'ai suivi aucune formation sur la technologie FPGA.
Il s'agit donc d'une version Alpha qui a très certainement besoin d'être améliorée.
Je publie quand-même ce code source en espérant qu'il pourra aider les débutants à programmer leur DE10-Nano.
Dans ce projet, j'ai eu l'occasion de survoler les points suivants:
- affichage de texte en utilisant le controleur HDMI
- échantillonnage de données audio + communication avec le controleur I2S
- manipulation de FIFO synchrone et asynchrone
- communication avec le HPS grâce au module Avalon-MM (nécessaire pour lire la carte SD et intercepter les évènements de la manette de jeu)
- création de PLL (permet de multiplier la fréquence d'horloge )
- utilisation de ROM et de RAM


## Le matériel pré-requis est le suivant:
- une carte DE10-Nano
- une carte d'extension avec plusieurs ports USB (ou MiSTer USB Hub 2.1)
https://ultimatemister.com/product/mister-usb-hub/
- un écran HDMI avec haut-parleur intégré
- une manette de jeu filaire
- une carte micro SD
- un cable mini-USB (pour transférer le programme FPGA)


## Logiciel pré-requis:
- Quartus Prime Lite Edition
- Format des audios: WAV , 16 bits, 44.1 KHz (CD audio standard)
- OS Linux avec un compilateur C++ sur le HPS du DE10-Nano
- Un client SSH pour se connecter au HPS (et pour transférer du programme HPS)


## Instruction pour l'installation de la partie FPGA:
1. Ouvrir le projet FPGA dans Quartus Prime
2. Lancer "Platform Designer" dans le menu "Tools"
3. Sélectionner "soc_system.qsys"
4. Cliquer sur "Generate HDL..." et "Generate", patienter quelques secondes, puis cliquer sur "Finish"
5. Compiler ensuite le projet
6. Enfin, transférer le programme FPGA sur la carte DE10-Nano 
	(A ce stade, vous devriez voir "WAVE PLAYER" s'afficher sur l'écran)

## Instruction pour l'installation de la partie HPS:
1. Avec un client SSH, se connecter au HPS
2. Créer le dossier "/root/music/"
3. Transférer vos audios wave dans ce dossier "music"
4. Transférer le fichier "HPS/sd_controller.cpp" dans le dossier "/root/"
5. Compiler avec la commande: g++ sd_controller.cpp -o sd_controller -lpthread
6. Puis lancer le script: /root/sd_conroller
 (Si vous avez bien tout suivi, votre liste d'audios devrait apparaitre à l'écran relié au DE10-Nano)

## Utilisation:
Les controles de la manette peuvent varier selon le modèle. Moi j'utilise une manette compatible pour la Switch de Nintendo, mais sinon vous devrez adapter les valeurs des boutons selon votre modèle.  
Si vous utilisez une manette compatible pour la Switch, alors voici les fonctions des touches:  
- la croix directionnelle: permet de sélectionner un audio
- le bouton B: permet de lancer la lecteur d'un audio
- le bouton A: permet de stopper une lecture






