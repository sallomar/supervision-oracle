# Qui bloque qui, et faut-il s'en inquiéter

`01-qui-bloque-qui.sql` répond à une seule question : quelle session en bloque une
autre, depuis combien de temps, et laquelle traiter.

## Ce que le script vérifie

1. **Les chaînes de blocage en cours.** Pour chaque session en attente : qui la bloque,
   avec le `STATUS` du bloqueur, depuis combien de temps il n'a plus envoyé d'appel, et
   un verdict porté sur l'attente **subie**.
2. **La tête de chaîne.** La session qui bloque sans être bloquée elle-même, avec le
   nombre de sessions qu'elle immobilise.
3. **L'objet contendu.** La table sur laquelle porte l'attente (`ROW_WAIT_OBJ#`).

## Pourquoi ça compte

Une session `INACTIVE` peut bloquer toute une application. Ce n'est pas une anomalie
Oracle, c'est son fonctionnement documenté : un verrou de ligne « exists until the
transaction commits or rolls back ». Il vit avec la **transaction**, pas avec l'activité
de la session. Et `STATUS = INACTIVE` signifie exactement « n'exécute pas de SQL en ce
moment », rien de plus. Un `UPDATE` suivi d'un utilisateur parti déjeuner sans valider
donne une session parfaitement inactive qui tient ses verrous, et les tiendra jusqu'au
`COMMIT`, au `ROLLBACK` ou à la déconnexion.

Deux lectures cohabitent dans la sortie, et il faut les deux :

| Colonne | Question à laquelle elle répond |
|---|---|
| `BLOQUEUR STATUT` + `BLOQUEUR DEPUIS` | Est-ce que ça va se résoudre tout seul ? Un bloqueur `ACTIVE` travaille, il finira. Un bloqueur `INACTIVE` ne rendra rien de lui-même. |
| `VERDICT (ATTENTE SUBIE)` | Ai-je encore le temps d'attendre ? Le seuil est du côté de la victime, pas du coupable. |

Les trois niveaux du verdict, mesurés sur l'attente de la session bloquée :

| Niveau | Attente | Ce que ça veut dire |
|---|---|---|
| `CRITIQUE` | plus de 30 min | L'impact utilisateur est déjà là, quel que soit l'état du bloqueur |
| `ATTENTION` | plus de 10 min | Ce n'est pas encore un incident, ça peut le devenir |
| `INFO` | 10 min ou moins | Comportement normal d'une base qui travaille |

Aucune des deux ne suffit seule. Un bloqueur `ACTIVE` qui fait attendre une session
depuis 40 minutes reste un incident ; un bloqueur `INACTIVE` depuis 2 heures que
personne n'attend n'en est pas un.

**Le piège de lecture** : `LAST_CALL_ET` change de sens selon le statut. Sur une session
`ACTIVE`, c'est la durée de l'appel en cours. Sur une session `INACTIVE`, c'est la durée
pendant laquelle elle **n'a rien envoyé**, transaction ouverte comprise. Le script écrit
donc « appel en cours depuis » ou « aucun appel depuis » au lieu de laisser un nombre de
minutes s'interpréter tout seul.

Autre conséquence, moins évidente : les listes de « sessions longues » filtrent
habituellement sur `STATUS = 'ACTIVE'`, parce que trier sur la durée de connexion remonte
en permanence des pools applicatifs connectés depuis des heures mais inactifs. Ce filtre
est le bon, et il rend la session `INACTIVE` bloquante **invisible** dans ces listes.
Seule la chaîne de blocage la montre.

## Aperçu de la sortie

```
SQL> @01-qui-bloque-qui.sql

=========================================================================
 QUI BLOQUE QUI  ==  lecture seule, aucune modification de la base
=========================================================================

=== SECTION 1 : chaines de blocage en cours =============================

BLOQUEUR BLOQUEUR           BLOQUEUR  BLOQUEUR                       BLOQUE BLOQUE             BLOQUE                          ATTENTE VERDICT
     SID UTILISATEUR        STATUT    DEPUIS                            SID UTILISATEUR        EVENEMENT D ATTENTE             MINUTES (ATTENTE SUBIE)
-------- ------------------ --------- ------------------------------ ------ ------------------ ------------------------------ -------- ---------------
     412 APP_PAIE           INACTIVE  aucun appel depuis 47 min          88 HR_ADMIN           enq: TX - row lock contention      43.2 CRITIQUE
     412 APP_PAIE           INACTIVE  aucun appel depuis 47 min         117 COMPTA             enq: TX - row lock contention      12.6 ATTENTION
     905 BATCH_USER         ACTIVE    appel en cours depuis 6 min       241 COMPTA             enq: TM - contention                4.1 INFO

3 lignes selectionnees.

=== SECTION 2 : tete(s) de chaine ======================================
 Celle qui bloque sans etre bloquee : la seule sur laquelle agir.

  TETE     TETE TETE               TETE           SANS APPEL SESSIONS                                                          DERNIER
   SID  SERIAL# UTILISATEUR        STATUT    OU ACTIVE (MIN) BLOQUEES PROGRAMME              MACHINE            UTILISATEUR OS SQL_ID
------ -------- ------------------ --------- --------------- -------- ---------------------- ------------------ -------------- ---------------
   412    20733 APP_PAIE           INACTIVE               47        2 JDBC Thin Client       appserv01          svc_paie       b2wq7fj5x3n0d
   905    41182 BATCH_USER         ACTIVE                  6        1 sqlplus.exe            appserv02          oracle         9zt4k1mqv0x8b

2 lignes selectionnees.

=== SECTION 3 : objets sur lesquels portent les attentes ===============

BLOQUE BLOQUE
   SID UTILISATEUR        PROPRIETAIRE         OBJET                          TYPE               FICHIER      BLOC
------ ------------------ -------------------- ------------------------------ ------------------ ------- ---------
    88 HR_ADMIN           COMPTA               ECRITURE                       TABLE                    7    284119
   117 COMPTA             COMPTA               ECRITURE                       TABLE                    7    284119

2 lignes selectionnees.

=========================================================================
 Fin. Aucune modification n a ete faite sur cette base.
=========================================================================
```

La tête de chaîne est ici `412`, `INACTIVE` depuis 47 minutes, et elle immobilise deux
sessions sur la même table. `905` bloque aussi, mais il travaille et son bloqué attend
4 minutes : ce n'est pas le même dossier.

**Où sont le `SERIAL#`, le programme, la machine.** En section 2. La section 1 situe, la
section 2 identifie celle sur laquelle on agit : c'est là qu'on a besoin du couple
`SID, SERIAL#`. Tout mettre sur une seule ligne rendait le tableau
illisible dans un terminal réel.

**Pourquoi la session `241` n'apparaît pas en section 3.** Elle est bien bloquée, mais pas
en attente d'un verrou de ligne : son `ROW_WAIT_OBJ#` vaut `-1`, et le filtre l'écarte.
C'est voulu. La documentation précise que ces colonnes ne sont valides que si la session
attend le commit d'une autre transaction ; sans ce filtre, la requête nommerait un objet
sans rapport, hérité de la dernière attente de la session. Sur une véritable attente de
verrou de ligne, `ROW_WAIT_OBJ#` est renseignée dès les premières fractions de seconde.
Une ligne absente de la section 3 signifie donc que la session attend **autre chose**
qu'un verrou de ligne : un verrou de table, une entrée ITL.

**Un objet non résolu s'affiche quand même.** Si la section 3 rend une ligne
`(non resolu) / OBJECT_ID 91204 / (autre conteneur)`, l'objet existe mais reste invisible
depuis le conteneur courant. Relance le script **dans la PDB concernée**. La section ne
laisse jamais tomber une ligne en silence : elle nomme l'objet, ou elle dit qu'elle n'y
arrive pas.

**Une section sans ligne est un résultat, pas un doute.** Le script laisse `FEEDBACK` actif
pour que `no rows selected` s'affiche explicitement.

**Si tu partages cette sortie** (ticket, capture d'écran, conversation avec un
prestataire), sache que la section 2 contient les colonnes `MACHINE` et `UTILISATEUR OS`
de la tête de chaîne. Sur un poste en domaine, elles portent le nom du domaine, celui de
la machine et l'identifiant de connexion. C'est précisément ce qui rend la section utile
pour savoir qui a lancé quoi, et ce qu'il faut masquer avant de diffuser.

## Ce que le script ne fait pas

Il s'arrête au diagnostic. Aucun `ALTER SYSTEM KILL SESSION`, pas même en commentaire :
terminer une session déclenche le `ROLLBACK` de sa transaction, qui peut durer aussi
longtemps que la transaction elle-même, et les verrous ne tombent qu'à la fin. Cela ne se
décide pas depuis un script. Si une décision doit être prise, elle porte sur la **tête de
chaîne** de la section 2 : libérer une session intermédiaire ne libère rien, elle se
remettra à attendre la même session.

## Privilèges requis

| Section | Vue | Privilège |
|---|---|---|
| 1, 2, 3 | `V$SESSION` | `SELECT` sur `V_$SESSION`, ou `SELECT_CATALOG_ROLE` |
| 3 | `DBA_OBJECTS` | `SELECT` sur `DBA_OBJECTS` |

Sans le droit sur `DBA_OBJECTS`, les sections 1 et 2 fonctionnent, et elles suffisent
pour agir. Aucune vue des packs Diagnostics ou Tuning n'est interrogée.

## Portée et limites

- **RAC : hors périmètre, et le script le dit.** Ces scripts visent les bases
  **single-instance**. `V$SESSION` est locale à l'instance : un `BLOCKING_SESSION` venu d'un
  autre nœud désignerait, dans la vue locale, une session sans aucun rapport portant le même
  `SID`. Le script refuse de faire cette résolution. La chaîne reste **affichée**, avec
  `(instance N)` en propriétaire et la mention `hors perimetre single-instance` : tu sais
  qu'un blocage existe et sur quel nœud il vit, et le script ne prétend pas le résoudre.
  *Affichage vérifié en forçant la condition d'instance sur une base mono-instance ; le cas
  RAC réel n'a pas pu être exécuté, faute de cluster. La borne, elle, est testée : sur une
  base mono-instance `BLOCKING_INSTANCE` vaut bien l'instance courante, et la chaîne se
  résout normalement.*
- **Fiabilité de la chaîne.** `BLOCKING_SESSION` n'est valide que si
  `BLOCKING_SESSION_STATUS` vaut `VALID` (les autres valeurs documentées sont `NO HOLDER`,
  `NOT IN WAIT` et `UNKNOWN`). Le script filtre dessus.
- **CDB / PDB : lance-le dans la PDB.** `V$SESSION` et `DBA_OBJECTS` n'ont pas la même
  portée. Depuis `CDB$ROOT`, `V$SESSION` remonte les sessions de **tous** les conteneurs
  (les vues `V$` sont des objets `CONTAINER_DATA`, et le périmètre dépend de l'attribut
  `CONTAINER_DATA` du compte) : les sections 1 et 2 répondent, et voient même davantage.
  Mais `DBA_OBJECTS` s'arrête au conteneur courant : un objet vivant dans une PDB n'y est
  pas. La section 3 affiche alors son `OBJECT_ID` et la mention `(non resolu)` au lieu de
  se taire : c'est le seul cas où elle ne peut pas nommer l'objet, et elle le dit.
  Vérifié sur une base multitenant : depuis la racine, sections 1 et 2 peuplées et objet
  non résolu ; depuis la PDB, les trois sections complètes.
- **Largeur d'affichage.** La sortie la plus large fait 150 caractères, ce qui tient dans
  une fenêtre standard. Le script pose `SET LINESIZE 240` pour que SQL*Plus ne coupe rien ;
  si ton terminal est plus étroit que 150 colonnes, c'est lui qui repliera les dernières
  colonnes. Élargis-le, ou `SPOOL` vers un fichier.
- **Durée.** Lecture mémoire, immédiate, sur les sections 1 et 2. Seule la section 3
  joint `DBA_OBJECTS`, dont le coût dépend du nombre d'objets de la base.
- **Versions : ce qui est visé, ce qui est vérifié.** Le script est écrit pour Oracle 11.2 et
  supérieur : il n'interroge que des colonnes de `V$SESSION` présentes de longue date et
  n'appelle aucune fonction dépendante d'une version récente. Il a été **exécuté sur Oracle
  21c Express Edition 21.0.0.0.0**, base multitenant, depuis `CDB$ROOT` et depuis une PDB, en
  `SYSDBA` puis avec un compte de lecture non privilégié. Il ne l'a **pas encore été sur 11.2
  ni sur 19c** : la compatibilité y est raisonnée, pas constatée. Si vous l'y passez, le retour
  m'intéresse.
- **Colonne `SECONDS_IN_WAIT`.** Le script l'utilise, alors que la documentation 19c la
  signale comme **dépréciée** au profit de `WAIT_TIME_MICRO` (précision à la microseconde).
  C'est un choix assumé : `SECONDS_IN_WAIT` reste servie de 11.2 à 19c, et la minute est la
  bonne unité pour décider s'il faut intervenir. Si tu préfères la colonne récente,
  `ROUND(w.wait_time_micro/1000000/60, 1)` remplace le calcul à l'identique.

## Sources

Comportement d'Oracle : *Oracle Database 19c Reference*, chapitre 9 `V$SESSION` (colonnes
`STATUS`, `LAST_CALL_ET`, `BLOCKING_SESSION_STATUS`, `BLOCKING_INSTANCE`, `ROW_WAIT_OBJ#`,
`SECONDS_IN_WAIT`) et chapitre 7 (`V$` / `GV$`) ; *Oracle Database 19c Concepts*,
chapitre 9, sections « Row Locks (TX) » et « Lock Duration ».

---

Nouveaux scripts régulièrement. Pour être prévenu,
**[suivez-moi sur LinkedIn](https://www.linkedin.com/in/omar-sall)**.
