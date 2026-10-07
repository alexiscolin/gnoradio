package safe

import (
	"strings"
	"testing"
)

// A sample of the 2026 content audit corpora: evasions that must be refused
// and real dedications that must pass.
const (
	attacks = `
fu-ck you
fu'ck off
f!u!c!k you
ff-uu-cc-kk you
nig-ger
cu-nt
wh-ore
bit-ch
pu-tain
fils de p-ute
va fan culo
k y s
fag-got
ped-ophile
p o r n
ƒuck
niggér
cünt
bítch
þwat
fæggot
Ñazi
fu(k
fcuk you
fukk you
b1tch
n166er
niqqa
nigguh
c0ck
pussi
kunt
sh1te
shiet
biotch
encu1e
pvtain
merd
conar
connar
enfoir3
nik ta mere
nique ta race
ftg
ferme ta gueule
nsfw
kill urself
kill yoself
unalive yourself
fucking
shitting
niggas
whores
dicks
cocksuckers
retarded
raped
fags
spics
dykes
pussies
assholes
connasse
salopes
enculee
tapette
gouine
negro
youpin
hurensohne
putas
maricon de mierda
froci
viados
kutwijf
mongool
kcuf
tnuc
shitface
jackass
cumdump
niggerlover
towelhead
gook
coon
porch monkey
white power
kill all muslims
heil hitler
14 88
holocaust was fake
k k k
praise bin laden
school shooting tomorrow
ill kill you
je vais te buter
creve sale chien
muérete
ti ammazzo
ik maak je dood
kill urself
kill your self
suicide is the answer
pends toi
bring dich um
doxx him
send gnot to
free gnot giveaway
claim free tokens
connect wallet to claim
wallet support
giveaway winner dm me
visit scam dot com
call 06 12 34 56 78
o6l2345678
061234 5678
+33 6
sit on my face
send nudes
im horny
deepthroat
jerk off
hand job
titties
onlyfans
sex
suce moi
nique
follar
ficken
pompino
neuken
lolicon
kiddy porn
hitlr
nazis were right
sale juif
sale noir
bicots dehors
kanake
gitan de merde
pute
mother fucker
fucka
fuckn
fkn
f you
loser kill yourself
arse
tosser
`
	dedications = `
Love you Fanny
For Assia, je t'aime
Big up Middlesex
The assassin of my heart
Reading Dickens tonight
For the pianist next door
Happy birthday Marie!
Feliz aniversário mãe
Habibi, enta omri
Ich liebe dich Schatz
Bisous mon coeur
For all the nurses
Buonanotte Napoli
Hello Cockburn family
Spurs till I die
Come on you Gunners
Dickinson poems for you
Chopin for Kasia
Pour Edith Piaf
Stairway to Heaven
Smells Like Teen Spirit
The Cramps rule
Mötley Crüe forever
Vanilla Fudge for Mark
Cumbia sonidera para Lupe
Mi gente, mi amor
Viva Mexico!
Para Puri y Paco
Felicidades Dolores
Desde Mazatlan con amor
Gruesse nach Wixhausen
Für Ursula zum Geburtstag
Ciao bella!
Ciao Peppino
Ola Porto!
Boa sorte Cuca
Groeten uit Lutjebroek
Doei Daan
Bonjour Vatan
Pour Coquelicot
Big up Dakar
Pour Rachid
Canim annem
Ozgur icin
Dla Wojtka
For Sunil Gavaskar fans
For Kamasutra book club
For Kim Dong-hyun
For Dung and Lan
For Anja Fichtel
For Mr Ho
Shoot for the stars
Drop dead gorgeous
Mad about you
God bless you
For the Muslim community
Black lives matter
Free Willy for kids
Lil Nas X for Monty
Eminem for Marshall
B52s for Fred
Happy 30th Ben
Since 1985
Sweet 16 Nina
Peacock dreams
Hello Scunthorpe United
Happiness for all
Butterscotch dreams
Massachusetts calling
Classic rock for Vince
Lassie come home
Hardcore fans unite
King Kong fans
Retro gamer
Nigeria, Naija!
Negroni sbagliato
Homeboy for Joe
Stupid Cupid for Connie
Blow your mind
Hot Hot Heat
Naked City
Pot of gold
Hash browns for breakfast
Shotgun wedding
Isis, I love you
Aryan Khan fans
Kill Em All for Lars
Die Antwoord for Ninja
Death in Vegas
Pedro, happy birthday
Pornichet beach day
Johnny Cash for June
Wankel engine
Hell's Kitchen
Bumble bee
Willy Wonka
Election day vibes
Shaggy for Orville
Testament for Chuck
Seminar day
Sextet for strings
Sexy Back for JT
Dickcissel bird
Kaka, Brazilian legend
Putanges, Orne
Chatterbox
Ridiculous love
Computadora nueva
Pollo asado
Puttanesca for dinner
Viadotto
Neukirchen-Vluyn
Enjoy yourself tonight
Bitte bleib bei mir
Salve Regina
Peter Gabriel for Kate
Seven Nation Army White
Dante's Inferno club
Scat singing Ella
Kinky Boots for Lola
Jouw beurt Daan
Tainted Love for Marc
Big black cat Felix
Sexuality is not a crime
Gerbe de fleurs
Mi burro Platero
Pinto beans
Monta Ellis fans
classic grass
Feliz cumpleaños
happy 25.12.2024
si te vas
to me and you
on a ride
ich liebe dich
dm for track ids
skill up, dude
grape season
ok ok ok
na na na hey
para mi abuela con cariño
wir fanden das Lied toll
grazie mille
spasibo bolshoe
la multi ani
maligayang kaarawan
wo ai ni
Shine on you crazy diamond
Hey Jude
the base camp
`
)

func TestCorpus(t *testing.T) {
	for _, s := range strings.Split(strings.TrimSpace(attacks), "\n") {
		if Note(s, 40) == "" {
			t.Errorf("passed: %q", s)
		}
	}
	for _, s := range strings.Split(strings.TrimSpace(dedications), "\n") {
		if why := Note(s, 40); why != "" {
			t.Errorf("refused: %q (%s)", s, why)
		}
	}
}
