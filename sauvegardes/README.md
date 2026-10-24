# Sauvegardes : jusqu'où pouvez-vous restaurer

*Un dossier de la série [supervision-oracle](../) : un script, une question.*

| Script | La question qu'il traite |
|---|---|
| [01-jusqu-ou-pouvez-vous-restaurer.sql](01-jusqu-ou-pouvez-vous-restaurer.sql) | Vous sauvegardez, mais **jusqu'où** pouvez-vous restaurer : le mode, la dernière sauvegarde, la chaîne des journaux, et l'écart en heures |

---

## 01. Jusqu'où pouvez-vous restaurer

`01-jusqu-ou-pouvez-vous-restaurer.sql` ne répond pas à « est-ce que ça sauvegarde ? »,
question à laquelle le compte rendu de la nuit répond déjà. Il répond à la seule qui
compte le jour où il faut restaurer : **à quel moment peut-on revenir, et qu'est-ce qui
sépare ce moment de maintenant**. Il ne garantit rien : seul un test de restauration
prouve qu'une sauvegarde est restaurable.

### Pourquoi ça compte

Une sauvegarde prise base ouverte n'est restaurable qu'avec les journaux archivés pendant
et après elle. Sans eux, elle ne ramène nulle part. Avec eux sur disque mais sans les avoir
sauvegardés, elle ramène au dernier journal sauvegardé, pas à maintenant. Le compte rendu
de la nuit ne dit rien de tout ça, et le script le lit en quatre temps.

**Le mode de journalisation décide de tout.** La documentation est nette : en
`NOARCHIVELOG`, « *the backup must be consistent; that is, you must shut down the database
cleanly before the backup* », et cette sauvegarde « *can be restored without further
recovery* ». Autrement dit, le seul point restaurable est la dernière sauvegarde cohérente,
base fermée, et tout ce qui a été écrit depuis est perdu. Le script l'écrit en toutes
lettres à la première ligne.

**Sur une base multitenant, la vue des travaux RMAN ne porte que le conteneur racine.**
C'est mesuré, pas supposé : sur la base de test, même compte, même base, `1` ligne depuis
`CDB$ROOT`, `0` depuis la PDB, deux minutes après une sauvegarde complète réussie. Un
script qui compte les travaux depuis une PDB conclut « aucune sauvegarde » sur une base
sauvegardée. **C'est l'inverse exact du script des licences**, qui se lance dans chaque PDB :
ici, lancez-le depuis la racine. Et quand ce n'est pas possible, le script le détecte et
le dit, au lieu de conclure à tort.

**Le fichier de contrôle garde une ligne par journal, même effacé, et par pièce, même
supprimée.** La politique de suppression des journaux archivés les efface une fois
sauvegardés, mais `V$ARCHIVED_LOG` garde l'enregistrement avec `DELETED = 'YES'`. Sur la
base de test : 2 lignes pour 1 seul journal encore sur disque. Même chose pour les pièces de
sauvegarde : `V$BACKUP_PIECE` garde celles que la purge des obsolètes a supprimées, en
statut `D`. Sur la base de test : 6 enregistrements depuis la racine, dont 5 disponibles.
Sans ces deux filtres, on compte ce qui n'existe plus.

**Une sauvegarde ouverte n'est restaurable qu'avec ses journaux.** La documentation :
« *A backup is called an inconsistent backup if it contains changes after its checkpoint. If
you have the archived redo logs needed to recover the backup, open database backups are as
effective for data protection as consistent backups.* » Le point jusqu'auquel on peut
revenir n'est donc pas la date de la dernière pièce : c'est **le dernier journal archivé
sauvegardé**. Une sauvegarde de la base lancée sans l'option qui sauvegarde aussi les
journaux laisse ce point en arrière, même si elle s'est terminée avec succès.

### Ce que le script vérifie

1. **Le mode et le conteneur.** `LOG_MODE` et sa lecture, puis le conteneur courant, avec
   l'avertissement de lancer le script depuis `CDB$ROOT`.
2. **La dernière sauvegarde réussie, par type**, lue dans `V$RMAN_BACKUP_JOB_DETAILS` :
   date, durée, volume, âge en heures, et une lecture face à trois repères par
   environnement : **48 h** en production, **192 h** en test, **336 h** en développement.
   Puis le **repli** : les pièces de sauvegarde du fichier de contrôle. Si la vue des
   travaux est vide mais que les pièces répondent, la lecture est `PILOTE DEPUIS LA
   RACINE, DETAIL NON VISIBLE D ICI`, jamais « aucune sauvegarde ».
3. **La chaîne et l'écart.** Journaux archivés encore sur disque, combien ne sont pas
   sauvegardés, le plus ancien d'entre eux, le dernier point restaurable et l'écart en
   heures jusqu'à maintenant. En `ARCHIVELOG`, le point restaurable est **le dernier
   journal archivé sauvegardé**, et rien d'autre ; en `NOARCHIVELOG`, la dernière pièce de
   sauvegarde. Si aucun journal n'a jamais été sauvegardé, le script l'écrit : `AUCUN
   JOURNAL SAUVEGARDE : POINT NON ETABLI`.
4. **Ce qui est configuré, et qui ne prouve rien.** La configuration RMAN explicite
   (rétention, sauvegarde automatique du fichier de contrôle, politique de suppression) et
   la zone de récupération en **usage effectif** : utilisé moins récupérable, parce
   qu'Oracle libère seul ce qui est récupérable, et que seul le reste peut saturer.

### Aperçu de la sortie

Depuis `CDB$ROOT`, sur une base dont la sauvegarde complète de la nuit a réussi mais dont
les journaux ne sont plus sauvegardés depuis deux jours :

```
SQL> @01-jusqu-ou-pouvez-vous-restaurer.sql

=========================================================================
 JUSQU OU POUVEZ-VOUS RESTAURER  ==  lecture seule, pas une garantie
=========================================================================

=== SECTION 1 : mode de journalisation et conteneur =====================
 Le mode decide de tout. Et depuis une PDB, la vue des travaux RMAN est
 vide par construction : lance ce script depuis CDB$ROOT.

BASE       JOURNALISATION OUVERTURE   LECTURE
---------- -------------- ----------- --------------------------------------------------------------
ORCL       ARCHIVELOG     READ WRITE  ARCHIVELOG : restauration possible jusqu au dernier journal

1 ligne selectionnee.

 (sur Oracle 11g la ligne suivante rend ORA-02003 : pas de conteneurs, attendu)

CONTENEUR COURANT
------------------------------
CDB$ROOT

1 ligne selectionnee.

=== SECTION 2 : la derniere sauvegarde reussie, par type ================
 Travaux RMAN termines, lus dans V$RMAN_BACKUP_JOB_DETAILS. Les seuils
 d age sont des reperes par environnement, pas un verdict.

                                     DUREE    VOLUME        AGE
TYPE             DERNIERE REUSSIE    (SEC)      (MO)   (HEURES) LECTURE (REPERES 48 / 192 / 336 H)
---------------- ---------------- -------- --------- ---------- ----------------------------------
DB FULL          23/10/2026 02:14     1874     48210       31.6 DANS LE REPERE PROD (48 H)
ARCHIVELOG       21/10/2026 02:31      212      3980       79.3 AU-DELA DU REPERE PROD (48 H)

2 lignes selectionnees.

     PIECES
DISPONIBLES DERNIERE PIECE   LECTURE
----------- ---------------- ------------------------------------------------------
         14 23/10/2026 02:14 DETAIL DES TRAVAUX CI-DESSUS

1 ligne selectionnee.

=== SECTION 3 : la chaine des journaux, et l ecart jusqu au point restaurable
 Une sauvegarde ouverte n est restaurable qu avec les journaux archives
 pendant et apres elle : le point restaurable est le dernier journal
 SAUVEGARDE. Ceux encore sur disque sans sauvegarde sont le retard.

  JOURNAUX    DONT NON PLUS ANCIEN      DERNIER POINT         ECART
SUR DISQUE SAUVEGARDES NON SAUVEGARDE   RESTAURABLE        (HEURES) LECTURE
---------- ----------- ---------------- ---------------- ---------- ----------------------------------------------
        61          37 21/10/2026 02:40 21/10/2026 02:31       79.3 JOURNAUX NON SAUVEGARDES : LE POINT EST EN RETARD

1 ligne selectionnee.

=== SECTION 4 : ce qui est configure, et qui ne prouve rien =============
 Une politique declaree n est pas une politique appliquee. Section RMAN
 vide : aucune configuration explicite, valeurs par defaut d Oracle.

CONFIGURATION RMAN             VALEUR
------------------------------ ------------------------------------------------------------
RETENTION POLICY               TO RECOVERY WINDOW OF 7 DAYS
CONTROLFILE AUTOBACKUP         ON
ARCHIVELOG DELETION POLICY     TO BACKED UP 1 TIMES TO DISK

3 lignes selectionnees.

                                                LIMITE    UTILISE RECUPERABLE      USAGE
ZONE DE RECUPERATION                              (GO)       (GO)        (GO) EFFECTIF % LECTURE (CRITIQUE A 90 % EFFECTIF)
-------------------------------------------- --------- ---------- ----------- ---------- ------------------------------------
/u01/app/oracle/fast_recovery_area               120.0      97.40       21.15       63.5 OK

1 ligne selectionnee.

=========================================================================
 Fin. Aucune modification n a ete faite sur cette base.
 Seul un test de restauration prouve qu une sauvegarde est restaurable.
=========================================================================
```

**Lecture.** La sauvegarde complète de la nuit a 31,6 heures et elle est dans le repère de
production. Tout a l'air en ordre, et c'est la section 3 qui dit le contraire : **37
journaux archivés sur 61 ne sont pas sauvegardés**, le plus ancien date du 21/10 à 02:40,
soit juste après la dernière sauvegarde de journaux réussie. Le dernier point restaurable
depuis les sauvegardes est donc **le 21/10 à 02:31, il y a 79 heures**, et non la
sauvegarde complète de la nuit : prise base ouverte, celle-ci a besoin des journaux
archivés pendant et après elle pour redevenir cohérente, et ces journaux ne sont que sur
disque. Si ce disque est perdu, tout ce qui a été écrit depuis le 21/10 l'est aussi. Le
compte rendu de la nuit disait « succès ». Il avait raison, et il ne répondait pas à la
bonne question.

La zone de récupération est à 63,5 % **effectifs** : 97,4 Go occupés dont 21,15 Go
qu'Oracle peut libérer seul. Un outil qui lit le brut annoncerait 81 %.

**Depuis une PDB**, la même base rend ceci en section 2 :

```
=== SECTION 2 : la derniere sauvegarde reussie, par type ================
 Travaux RMAN termines, lus dans V$RMAN_BACKUP_JOB_DETAILS. Les seuils
 d age sont des reperes par environnement, pas un verdict.

aucune ligne selectionnee

     PIECES
DISPONIBLES DERNIERE PIECE   LECTURE
----------- ---------------- ------------------------------------------------------
          6 23/10/2026 02:14 PILOTE DEPUIS LA RACINE, DETAIL NON VISIBLE D ICI

1 ligne selectionnee.
```

La vue des travaux ne rend rien, les pièces du fichier de contrôle répondent : le script
dit où regarder au lieu de dire qu'il n'y a rien. Les sections 1, 3 et 4 restent lisibles
depuis la PDB.

### Ce que le script ne fait pas

- **Il ne garantit pas une restauration.** Une pièce de sauvegarde présente dans le
  fichier de contrôle peut être corrompue, déplacée ou effacée du disque sans que la vue le
  sache. Seul un `RESTORE ... VALIDATE` ou un vrai test de restauration le prouve, et ce
  script n'en lance aucun.
- **Il ne voit que ce que RMAN a enregistré dans le fichier de contrôle.** Les copies
  faites hors RMAN n'y sont pas. Et les enregistrements du fichier de contrôle sont
  réutilisés après un âge minimal fixé par `CONTROL_FILE_RECORD_KEEP_TIME` : une sauvegarde
  plus ancienne que ce délai peut avoir disparu de la vue tout en existant sur bande.
- **Il n'utilise ni `V$BACKUP`, ni `V$BACKUP_DATAFILE`, ni `V$DATAFILE_HEADER`**, souvent
  refusées à un compte de lecture. Il ne lit aucune vue sous licence.

### Vérifier que le script détecte

Sur une base de **test** uniquement. Ce sujet a une particularité : **les deux chemins du
script se vérifient sur la même base, sans rien provoquer**, dès lors qu'elle est en
`ARCHIVELOG` avec au moins une sauvegarde RMAN.

1. Lance le script depuis `CDB$ROOT` (`sqlplus / as sysdba` y atterrit). La section 2 doit
   lister les travaux, et le repli dire `DETAIL DES TRAVAUX CI-DESSUS`.
2. Lance-le dans une PDB, avec un compte de lecture non privilégié. La section 2 doit
   rendre `aucune ligne selectionnee` pour les travaux, puis le repli `PILOTE DEPUIS LA
   RACINE, DETAIL NON VISIBLE D ICI` avec un nombre de pièces **inférieur** à celui de la
   racine : la PDB ne voit que les pièces partagées et les siennes. Sur la base de test :
   **5 pièces disponibles depuis la racine, 2 depuis la PDB** (6 et 3 enregistrements dans
   le fichier de contrôle, dont un en statut `D` de chaque côté, que le script ne compte pas).
3. Compare la section 3 : même nombre de journaux depuis les deux conteneurs, et un écart
   identique. C'est la preuve que la chaîne, elle, se lit de partout.

**Pour voir la section 3 basculer en `JOURNAUX NON SAUVEGARDES`**, il suffit de faire
tourner la base sans sauvegarder ses journaux : quelques `ALTER SYSTEM SWITCH LOGFILE` en
SYSDBA créent des journaux archivés, et `DONT NON SAUVEGARDES` monte tant qu'aucun
`BACKUP ARCHIVELOG ALL` n'a tourné. Remise en état : relancer la sauvegarde des journaux,
la colonne revient à 0. Cette provocation n'a **pas** été exécutée pour ce dépôt : la
base de test a été lue telle qu'elle était, avec sa chaîne complète.

Deux pièges de manipulation : un commentaire `--` placé sur la même ligne qu'un `;`
empêche l'instruction de s'exécuter, et pour ce script `sqlplus / as sysdba` est **le bon
endroit** : c'est depuis la racine qu'on voit les travaux.

### Privilèges requis

| Section | Vue | Privilège |
|---|---|---|
| 1 | `V$DATABASE` | `SELECT` sur `V_$DATABASE`, ou `SELECT_CATALOG_ROLE` |
| 2 | `V$RMAN_BACKUP_JOB_DETAILS`, `V$BACKUP_PIECE` | `SELECT` sur `V_$RMAN_BACKUP_JOB_DETAILS` et `V_$BACKUP_PIECE`, ou `SELECT_CATALOG_ROLE` |
| 3 | `V$ARCHIVED_LOG`, `V$BACKUP_PIECE`, `V$DATABASE` | idem |
| 4 | `V$RMAN_CONFIGURATION`, `V$RECOVERY_FILE_DEST` | `SELECT` sur `V_$RMAN_CONFIGURATION` et `V_$RECOVERY_FILE_DEST`, ou `SELECT_CATALOG_ROLE` |

Aucune vue sous licence. Exécuté avec un compte de lecture non privilégié, depuis la PDB.

### Portée et limites

- **CDB / PDB : lance-le depuis `CDB$ROOT`.** `V$RMAN_BACKUP_JOB_DETAILS` ne porte que
  `CON_ID = 1`. Depuis une PDB elle est vide par construction, et le script le signale au
  lieu de conclure. `V$BACKUP_PIECE` est partiellement visible depuis une PDB (pièces
  partagées et pièces propres), `V$ARCHIVED_LOG`, `V$RMAN_CONFIGURATION` et
  `V$RECOVERY_FILE_DEST` répondent de partout.
- **Le détail de la zone de récupération par type est filtré par conteneur.**
  `V$RECOVERY_AREA_USAGE` donne, pour la même zone, des pourcentages différents selon le
  conteneur d'où on la lit (sur la base de test : 14,8 % depuis la racine, 3,3 % depuis la
  PDB). Le script lit `V$RECOVERY_FILE_DEST`, dont les totaux sont les mêmes partout.
- **Les repères d'âge ont une origine, et une limite.** 48 h, 192 h et 336 h sont les
  repères par environnement d'une supervision continue, et ils y servent de **repli** : le
  vrai seuil y suit la cadence détectée de chaque base. Une production sauvegardée chaque
  semaine n'est pas en retard à 50 heures. Le script affiche les trois repères et vous
  laisse choisir le vôtre ; il ne connaît pas votre environnement.
- **`NOARCHIVELOG`.** La section 3 n'a pas de chaîne à lire et le dit : le point
  restaurable est la dernière sauvegarde cohérente. Ce cas n'a pas été exécuté pour ce
  dépôt, la base de test ayant été passée en `ARCHIVELOG` avant publication.
- **RAC : hors périmètre.** Un seul fil de journaux est supposé.
- **Oracle 11g.** La ligne `CONTENEUR COURANT` rend `ORA-02003` : il n'y a pas de
  conteneurs, le reste du script s'exécute normalement.
- **Versions : ce qui est visé, ce qui est vérifié.** Écrit pour Oracle 11.2 et
  supérieur : aucune syntaxe récente, les vues utilisées existent depuis 10g. Exécuté sur
  **Oracle 21c Express Edition 21.0.0.0.0**, base multitenant en `ARCHIVELOG` avec une
  sauvegarde RMAN complète, depuis `CDB$ROOT` en `SYSDBA` et depuis la PDB avec un compte
  de lecture non privilégié. Pas encore exécuté sur 11.2 ni sur 19c, ni sur une base en
  `NOARCHIVELOG` : l'aperçu ci-dessus est fictif.

### Sources

Comportement d'Oracle : *Oracle Database 19c Reference*, chapitre 8.172
`V$RMAN_BACKUP_JOB_DETAILS`, chapitre 7.101 `V$BACKUP_PIECE` (« *information about
backup pieces from the control file* »), chapitre 7.35 `V$ARCHIVED_LOG` (enregistrement
inséré après archivage ; `NAME` à `NULL` si le journal a été effacé) ; *Oracle Database 19c
Backup and Recovery User's Guide*, § 2.4.2 (sauvegarde ouverte dite *inconsistent*,
« *as effective… if you have the archived redo logs needed to recover the backup* »),
§ 2.4.3 et § 29.2 (en `NOARCHIVELOG`, seule une sauvegarde cohérente est valide, et « *you
would lose any transactions made after the backup* »), et chapitre sur la gestion des
enregistrements du fichier de contrôle (`CONTROL_FILE_RECORD_KEEP_TIME`).

---

Nouveaux scripts régulièrement. Pour être prévenu,
**[suivez-moi sur LinkedIn](https://www.linkedin.com/in/omar-sall)**.

Je construis **Deynao**, la supervision continue des parcs Oracle on-premise : en lecture
seule, sans agent sur les serveurs de bases, aucun flux transmis à l'éditeur. En phase
d'évaluation, sur vos propres bases : [deynao.fr](https://deynao.fr)
