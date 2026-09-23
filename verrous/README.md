# Verrous : diagnostiquer un blocage

*Un dossier de la série [supervision-oracle](../) : un script, une question.*

| Script | La question qu'il traite |
|---|---|
| [01-qui-bloque-qui.sql](01-qui-bloque-qui.sql) | Quelle session en bloque une autre, depuis combien de temps, et laquelle traiter |
| [02-blocage-sans-verrou-oracle.sql](02-blocage-sans-verrou-oracle.sql) | L'application est bloquée et il n'y a **aucun** verrou Oracle : le verrou applicatif |

---

## 01. Qui bloque qui, et faut-il s'en inquiéter

`01-qui-bloque-qui.sql` répond à une seule question : quelle session en bloque une
autre, depuis combien de temps, et laquelle traiter.

### Ce que le script vérifie

1. **Les chaînes de blocage en cours.** Pour chaque session en attente : qui la bloque,
   avec le `STATUS` du bloqueur, depuis combien de temps il n'a plus envoyé d'appel, et
   un verdict porté sur l'attente **subie**.
2. **La tête de chaîne.** La session qui bloque sans être bloquée elle-même, avec le
   nombre de sessions qu'elle immobilise.
3. **L'objet contendu.** La table sur laquelle porte l'attente (`ROW_WAIT_OBJ#`).

### Pourquoi ça compte

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

### Aperçu de la sortie

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

### Ce que le script ne fait pas

Il s'arrête au diagnostic. Aucun `ALTER SYSTEM KILL SESSION`, pas même en commentaire :
terminer une session déclenche le `ROLLBACK` de sa transaction, qui peut durer aussi
longtemps que la transaction elle-même, et les verrous ne tombent qu'à la fin. Cela ne se
décide pas depuis un script. Si une décision doit être prise, elle porte sur la **tête de
chaîne** de la section 2 : libérer une session intermédiaire ne libère rien, elle se
remettra à attendre la même session.

### Privilèges requis

| Section | Vue | Privilège |
|---|---|---|
| 1, 2, 3 | `V$SESSION` | `SELECT` sur `V_$SESSION`, ou `SELECT_CATALOG_ROLE` |
| 3 | `DBA_OBJECTS` | `SELECT` sur `DBA_OBJECTS` |

Sans le droit sur `DBA_OBJECTS`, les sections 1 et 2 fonctionnent, et elles suffisent
pour agir. Aucune vue des packs Diagnostics ou Tuning n'est interrogée.

### Portée et limites

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

### Sources

Comportement d'Oracle : *Oracle Database 19c Reference*, chapitre 9 `V$SESSION` (colonnes
`STATUS`, `LAST_CALL_ET`, `BLOCKING_SESSION_STATUS`, `BLOCKING_INSTANCE`, `ROW_WAIT_OBJ#`,
`SECONDS_IN_WAIT`) et chapitre 7 (`V$` / `GV$`) ; *Oracle Database 19c Concepts*,
chapitre 9, sections « Row Locks (TX) » et « Lock Duration ».

---

## 02. Blocage sans verrou Oracle

`02-blocage-sans-verrou-oracle.sql` traite le cas le plus déroutant : l'application est
bloquée, et la base n'a **rien**. Pas de session bloquante, pas de contention, pas de
transaction anormale. La supervision a raison, et l'application est quand même par terre.

### Pourquoi ça compte

Il existe deux familles de verrous applicatifs, et une seule est visible.

| Famille | Posé par | Visible dans les vues Oracle ? | Survit à un redémarrage ? |
|---|---|---|---|
| Verrou `UL` | `DBMS_LOCK` | **Oui** : `V$LOCK`, type `UL` | Non : libéré à la fin de la session |
| Verrou logique | une **ligne dans une table** (Liquibase `DATABASECHANGELOGLOCK`, quartz, mutex maison) | **Non, jamais** | **Oui** : c'est une donnée validée |

La première famille est un vrai verrou Oracle. La documentation de `DBMS_LOCK` le dit :
« User locks never conflict with Oracle locks because they are identified with the prefix
UL. » Il a la détection de deadlock, il se voit, il meurt avec sa session. Beaucoup de DBA
n'ont simplement jamais filtré `V$LOCK` sur ce type.

La seconde n'est pas un verrou au sens d'Oracle. C'est une ligne : `LOCKED = 1`, une date,
un nom de serveur. Quand l'outil de migration meurt avant de la remettre à zéro, elle
reste. L'application refuse alors de démarrer, en attente d'un verrou que plus personne ne
tient. Redémarrer l'instance Oracle ne change rien : une donnée validée survit à tout.
Et pendant ce temps, chaque vue de verrouillage de la base dit, à raison, qu'il n'y a
rien à signaler. Le pire n'est pas la panne, c'est la conclusion qu'on en tire : « le
problème n'est pas la base », et l'incident part chercher ailleurs.

### Ce que le script vérifie

1. **Les verrous applicatifs visibles.** `V$LOCK` filtré sur le type `UL` : qui détient,
   qui attend, quel identifiant applicatif, depuis combien de temps.
2. **Les tables de verrou logique Liquibase accessibles.** Découvertes dans `ALL_TABLES`,
   tous schémas confondus.
3. **La requête à lancer, générée pour chaque table trouvée.** Le script ne peut pas
   connaître d'avance le schéma qui porte la table, et il refuse de lire une table
   applicative de lui-même : il **génère** le `SELECT` exact, verdict compris, et la
   décision de l'exécuter t'appartient.

### Aperçu de la sortie

```
SQL> @02-blocage-sans-verrou-oracle.sql

=========================================================================
 BLOCAGE SANS VERROU ORACLE  ==  lecture seule, aucune modification
=========================================================================

=== SECTION 1 : verrous applicatifs visibles (DBMS_LOCK, type UL) ======

                                                     ID1                    AGE
ETAT        SID UTILISATEUR        STATUT     APPLICATIF MODE           MINUTES
-------- ------ ------------------ --------- ----------- ------------- --------
DETIENT    2203 BATCH_USER         INACTIVE        12345 Exclusive          184
ATTEND      947 APP_PAIE           ACTIVE          12345 Exclusive           12

2 lignes selectionnees.

=== SECTION 2 : tables de verrou logique Liquibase accessibles =========
 Un verrou logique ne se voit que dans SA table. Section vide : aucune
 table DATABASECHANGELOGLOCK accessible a ce compte.

PROPRIETAIRE              TABLE
------------------------- -------------------------
APP_PAIE                  DATABASECHANGELOGLOCK

1 ligne selectionnee.

=== SECTION 3 : requete a lancer, generee par table trouvee ============
 A copier-coller telle quelle. Le script ne lit jamais une table
 applicative de lui-meme : la decision de la lire t appartient.

-- APP_PAIE.DATABASECHANGELOGLOCK :
SELECT id,
       locked,
       TO_CHAR(lockgranted, 'DD/MM/YYYY HH24:MI:SS') AS pose_le,
       CAST(lockedby AS VARCHAR2(30)) AS pose_par,
       CASE WHEN locked = 0 THEN 'OK'
            WHEN lockgranted IS NULL THEN 'A CONTROLER : verrou pose sans date'
            WHEN lockgranted < SYSDATE - 2/24 THEN 'CRITICAL : pose depuis plus de 2 h'
            WHEN lockgranted < SYSDATE - 30/1440 THEN 'WARNING : pose depuis plus de 30 min'
            ELSE 'OK : migration recente' END AS verdict
FROM "APP_PAIE"."DATABASECHANGELOGLOCK";

12 lignes selectionnees.

=========================================================================
 Fin. Aucune modification n a ete faite sur cette base.
=========================================================================
```

Ici la section 1 montre au passage un vrai cas d'école : le `UL` `12345` est détenu par
une session `INACTIVE` depuis 3 heures, et une session `ACTIVE` l'attend depuis 12
minutes. Même invisible des outils habituels, cette famille-là se diagnostique.

La requête générée, exécutée telle quelle dans la même session, rend une ligne par verrou :

```
        ID     LOCKED POSE_LE           POSE_PAR                       VERDICT
---------- ---------- ----------------- ------------------------------ ------------------------------------
         1          1 15/09/2026 02:58  appserv01                      CRITICAL : pose depuis plus de 2 h
```

**Lance-la dans la session où tu viens de lancer le script**, qui a posé `SET LINESIZE
240`. La requête borne elle-même la largeur de ses colonnes, parce que `LOCKEDBY` est un
`VARCHAR2(255)` et déborderait sinon. Mais une session neuve démarre à `LINESIZE 80`,
trop étroit pour cinq colonnes.

**Les seuils du verdict généré** : `WARNING` au-delà de 30 minutes, `CRITICAL` au-delà de
2 heures. Ce sont des valeurs par défaut : adapte-les à la durée normale des migrations
de ton application.

**Si le verdict tombe sur un verrou orphelin**, la libération est un `UPDATE` sur la table
applicative : elle se décide avec l'équipe applicative, après avoir vérifié qu'aucune
migration n'est réellement en cours, et elle n'appartient pas à un script de diagnostic.

### Vérifier que le script détecte

Sur une base de **test** uniquement. Les deux familles se provoquent sans risque.

**Famille 1, le verrou `UL`** : dans une première session, poser un verrou et laisser la
session ouverte :

```sql
DECLARE
  ret NUMBER;
BEGIN
  ret := DBMS_LOCK.REQUEST(id => 12345, lockmode => DBMS_LOCK.X_MODE,
                           timeout => 0, release_on_commit => FALSE);
END;
/
```

Dans une seconde session, lancer le script : la section 1 doit montrer `DETIENT`,
l'identifiant `12345`, le mode `Exclusive`. Fermer la première session libère le verrou
(comportement documenté de `DBMS_LOCK`) : relancer le script doit rendre la section vide.

**Famille 2, le verrou logique** : créer la situation de l'incident type, un verrou posé
puis jamais relâché :

```sql
CREATE TABLE databasechangeloglock
  (id NUMBER, locked NUMBER(1), lockgranted TIMESTAMP, lockedby VARCHAR2(255));
INSERT INTO databasechangeloglock
  VALUES (1, 1, SYSTIMESTAMP - INTERVAL '3' HOUR, 'appserv01');
COMMIT;
```

Lancer le script : la section 2 trouve la table, la section 3 génère la requête. Exécuter
la requête générée **dans la même session** : le verdict doit être `CRITICAL : pose depuis
plus de 2 h`.

Pour rejouer avec un compte de lecture, il faut sortir de SQL\*Plus avant de relancer la
commande : `sqlplus` tapé à l'invite `SQL>` rend un `SP2-0734`, pas une connexion.

**Remise en état, obligatoire :**

```sql
DROP TABLE databasechangeloglock PURGE;
SELECT COUNT(*) FROM v$lock WHERE type = 'UL';   -- doit rendre 0 apres fermeture des sessions
```

Deux pièges de manipulation : un commentaire `--` placé sur la même ligne qu'un `;` empêche
l'instruction de s'exécuter, et `sqlplus / as sysdba` se connecte dans `CDB$ROOT`, pas dans
la PDB. Vérifier où l'on est : `SELECT SYS_CONTEXT('USERENV','CON_NAME') FROM dual;`

### Privilèges requis

| Section | Vue | Privilège |
|---|---|---|
| 1 | `V$LOCK`, `V$SESSION` | `SELECT` sur `V_$LOCK` et `V_$SESSION`, ou `SELECT_CATALOG_ROLE` |
| 2, 3 | `ALL_TABLES` | aucun privilège particulier : la vue montre ce que le compte peut lire |

C'est la nuance des sections 2 et 3 : `ALL_TABLES` décrit « les tables accessibles à
l'utilisateur courant ». Une table `DATABASECHANGELOGLOCK` qui existe mais sur laquelle
ton compte n'a aucun droit **n'apparaîtra pas**. Une section 2 vide signifie donc « rien
d'accessible », pas « rien nulle part » : si l'application utilise Liquibase et que la
section reste vide, demande un `GRANT SELECT` sur sa table de verrou.

### Portée et limites

- **RAC : hors périmètre.** `V$LOCK` est locale à l'instance : un verrou `UL` tenu sur un
  autre nœud n'apparaît pas ici. Le verrou logique, lui, est une donnée : il est visible
  de tous les nœuds, mais c'est la seule partie du script qui le soit.
- **CDB / PDB : lance-le dans la PDB.** Les tables applicatives ne sont pas visibles
  depuis `CDB$ROOT` : la section 2 y est vide, et c'est le comportement attendu. La
  section 1, elle, voit les `UL` de tous les conteneurs depuis la racine.
- **Fuseau horaire.** `LOCKGRANTED` est écrit par la JVM de l'outil de migration, en heure
  locale de son serveur. Si le serveur applicatif et la base ne sont pas sur le même
  fuseau, l'âge calculé par le verdict est décalé d'autant. En cas de doute, comparer
  `LOCKGRANTED` à l'heure du serveur applicatif, pas à celle de la base.
- **Flyway.** Son mécanisme de verrouillage est différent de celui de Liquibase et n'est
  pas couvert par ce script. Le principe de diagnostic reste le même : le verrou d'un
  outil de migration se cherche dans ses tables, pas dans `V$LOCK`.
- **Versions : ce qui est visé, ce qui est vérifié.** Écrit pour Oracle 11.2 et supérieur :
  `V$LOCK`, `V$SESSION` et `ALL_TABLES` sont servies de longue date, et la génération de la
  section 3 n'utilise que `CONNECT BY`. Exécuté sur **Oracle 21c Express Edition
  21.0.0.0.0**, base multitenant, depuis la PDB et depuis `CDB$ROOT`, en `SYSDBA` puis avec
  un compte de lecture non privilégié. Pas encore exécuté sur 11.2 ni sur 19c.

### Sources

Comportement d'Oracle : *Oracle Database 19c Reference*, chapitre 8.40 `V$LOCK` (types
utilisateur `TM`, `TX`, `UL`, colonnes `CTIME`, `LMODE`, `REQUEST`) et chapitre 3.120
`ALL_TABLES` ; *Oracle Database 19c PL/SQL Packages and Types Reference*, chapitre 96
`DBMS_LOCK` (préfixe « UL », libération en fin de session).

---

Nouveaux scripts régulièrement. Pour être prévenu,
**[suivez-moi sur LinkedIn](https://www.linkedin.com/in/omar-sall)**.

Je construis **Deynao**, la supervision Oracle 100 % on-premise qui fait ces contrôles
en continu : [deynao.fr](https://deynao.fr)
