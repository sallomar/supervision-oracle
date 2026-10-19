# Licences : ce que votre base a activé sans vous le dire

*Un dossier de la série [supervision-oracle](../) : un script, une question.*

| Script | La question qu'il traite |
|---|---|
| [01-options-activees-sans-le-savoir.sql](01-options-activees-sans-le-savoir.sql) | Quelles fonctionnalités à licence séparée ont été **observées en usage**, depuis quand, et si c'est Oracle ou vous qui les avez déclenchées |

---

## 01. Les options activées sans le savoir

`01-options-activees-sans-le-savoir.sql` lit la vue qu'un audit de licence lit, et la rend
interprétable : édition et conteneur d'abord, fraîcheur de la mesure ensuite, puis les
usages observés, puis ce qui n'est qu'installé. **Ce n'est pas un audit** : seul votre
contrat Oracle détermine vos droits, et ce script ne qualifie jamais une conformité.

### Pourquoi ça compte

Beaucoup d'options Oracle s'activent **à l'usage**. Un `CREATE TABLE ... PARTITION BY`
tapé pour bien faire, un conseil de l'assistant de réglage accepté un jour de pointe : rien
ne prévient, rien ne demande confirmation. Un job interne passe ensuite périodiquement,
note ce qu'il a vu dans `DBA_FEATURE_USAGE_STATISTICS`, et garde la **première date**. Sur
la base de test de ce dépôt, 13 détections entre le 13/07 et le 14/10 : un passage par
semaine.

Cette vue ne coûte rien à lire, et elle est rarement lue avant qu'on la demande. Trois
choses la rendent trompeuse si on la lit brute, et le script les traite une par une.

**`CURRENTLY_USED` est une photo, pas un historique.** La documentation le dit mot pour
mot : « usage détecté **la dernière fois que le système a vérifié** ». Une activation
postérieure au dernier échantillon n'est pas encore dedans. Une section vide prouve donc
seulement qu'il n'y avait rien **à cette date**. Le script affiche cette date en tête, et
son âge en jours.

**`V$OPTION` à `TRUE` n'est pas un usage.** La documentation de la vue : la valeur
« indique si l'option est **installée** ». C'est l'état des binaires, et sur une édition
Enterprise la plupart des options le sont. Confondre « installée » et « utilisée »
est l'erreur la plus fréquente sur ce sujet, dans les deux sens : elle fait acheter ce
qu'on n'utilise pas, ou ignorer ce qu'on utilise. Le script les montre dans deux sections
distinctes, sous leur vrai nom.

**L'édition change tout.** Oracle Database Express Edition et Personal Edition sont
distribuées sous leur propre licence, qui couvre ce que contiennent leurs binaires, dans
les limites de l'édition. Un usage de Partitioning sur une XE n'est pas une exposition.
Le script lit l'édition en premier et adapte sa colonne `LECTURE` : sur ces éditions, tout
est `INCLUS DANS L EDITION`.

### Ce que le script vérifie

1. **Situer.** Édition et version (`V$VERSION`), nom de la base, conteneur courant, puis
   la fraîcheur de la vue : date du dernier échantillon, âge, nombre de fonctionnalités
   suivies, en usage, et en usage parmi celles à licence séparée.
2. **Les usages observés.** Les fonctionnalités à licence séparée marquées en usage au
   dernier échantillon, avec le nombre de détections, la première et la dernière date,
   l'**origine** (`SYSTEME` quand c'est Oracle lui-même : suffixe `(system)`, tâches de
   maintenance automatique, objets du dictionnaire ; sinon `UTILISATEUR`) et une
   **lecture** qui n'est jamais un verdict : `A RAPPROCHER DU CONTRAT`, `USAGE INTERNE
   ORACLE` ou `INCLUS DANS L EDITION`.
3. **Installé et configuré.** Les options potentiellement soumises à licence séparée,
   selon l'édition, présentes dans `V$OPTION`, le
   paramètre `control_management_pack_access` et sa lecture (aucun pack, Diagnostics,
   Diagnostics et Tuning), et `V$LICENSE` : plafond de sessions, pic depuis le
   démarrage, plafond d'utilisateurs nommés. `0` y signifie « aucune limite configurée »,
   pas « zéro licence ».

### Aperçu de la sortie

```
SQL> @01-options-activees-sans-le-savoir.sql

=========================================================================
 OPTIONS ACTIVEES SANS LE SAVOIR  ==  lecture seule, pas un audit
=========================================================================

=== SECTION 1 : edition, conteneur, et fraicheur de la vue ==============
 Rien de ce qui suit ne se lit sans ces trois informations.

EDITION ET VERSION (V$VERSION)
------------------------------------------------------------------------
Oracle Database 19c Enterprise Edition Release 19.0.0.0.0 - Production

1 ligne selectionnee.

BASE
------------
ORCL

1 ligne selectionnee.
 (sur Oracle 11g la ligne suivante rend ORA-02003 : pas de conteneurs, attendu)

CONTENEUR COURANT
------------------------------
ORCLPDB1

1 ligne selectionnee.

DERNIER ECHANTILLON      AGE   LIGNES EN USAGE        EN USAGE
DE LA VUE            (JOURS)  SUIVIES  (TOTAL)  (LIC. SEPAREE)
------------------- -------- -------- -------- ---------------
18/10/2026 03:00:12      1.3      312       41               3

1 ligne selectionnee.

=== SECTION 2 : fonctionnalites a licence separee OBSERVEES en usage ====
 Dans CE conteneur, au dernier echantillon. Section vide : aucune
 fonctionnalite de la liste n y etait detectee en usage a cette date.

                                                   DETEC- PREMIERE   DERNIERE
FONCTIONNALITE (DBA_FEATURE_USAGE_STATISTICS)       TIONS DETECTION  DETECTION  ORIGINE     LECTURE
------------------------------------------------ -------- ---------- ---------- ----------- ------------------------
Partitioning                                           32 11/03/2026 18/10/2026 UTILISATEUR A RAPPROCHER DU CONTRAT
Automatic Maintenance - SQL Tuning Advisor             61 22/08/2025 18/10/2026 SYSTEME     USAGE INTERNE ORACLE
Partitioning (system)                                  61 22/08/2025 18/10/2026 SYSTEME     USAGE INTERNE ORACLE

3 lignes selectionnees.

=== SECTION 3 : installe et configure, ce qui N EST PAS un usage =========
 V$OPTION dit ce que les binaires contiennent, pas ce qui sert. Un pack
 ouvert est une configuration, pas un usage : l usage se lit en section 2.

OPTION (V$OPTION)              ETAT
------------------------------ ----------------------------------
Advanced Analytics             INSTALLEE, PAS FORCEMENT UTILISEE
Advanced Compression           INSTALLEE, PAS FORCEMENT UTILISEE
OLAP                           INSTALLEE, PAS FORCEMENT UTILISEE
Partitioning                   INSTALLEE, PAS FORCEMENT UTILISEE
Real Application Testing       INSTALLEE, PAS FORCEMENT UTILISEE
Spatial                        INSTALLEE, PAS FORCEMENT UTILISEE

6 lignes selectionnees.

PARAMETRE                       VALEUR             LECTURE
------------------------------- ------------------ ------------------------------------
control_management_pack_access  DIAGNOSTIC+TUNING  DIAGNOSTICS ET TUNING PACK OUVERTS

1 ligne selectionnee.

PLAFOND SESSIONS          PIC DEPUIS PLAFOND UTILISATEURS
(SESSIONS_MAX)             DEMARRAGE NOMMES (USERS_MAX)
------------------------ ----------- ------------------------
AUCUNE LIMITE CONFIGUREE         187 AUCUNE LIMITE CONFIGUREE

1 ligne selectionnee.

=========================================================================
 Fin. Aucune modification n a ete faite sur cette base.
 Ceci n est pas un audit : seul votre contrat Oracle determine vos droits.
=========================================================================
```

**Lecture de la section 2.** Trois fonctionnalités de la liste sont en usage. Deux sont
d'origine `SYSTEME` : `Partitioning (system)` est le partitionnement des tables internes
d'Oracle, et l'assistant de réglage automatique tourne dans les fenêtres de maintenance
sans que personne ne l'ait lancé. Ces usages sont partout, et un audit sait les lire. La
première ligne est différente : `Partitioning` sans suffixe, **32 détections depuis le
11/03/2026**, donc une table partitionnée par quelqu'un, présente depuis sept mois. C'est
la ligne qu'il faut rapprocher du contrat. Le script ne dit pas si elle est couverte,
il n'en a pas les moyens : il dit qu'elle existe, et depuis quand.

**Lecture de la section 3.** Six options installées, ce qui est l'état normal d'une
édition Enterprise, et aucune de ces lignes ne signifie un usage. La liste est celle des
options potentiellement soumises à licence séparée : ce caractère dépend de l'édition, et
certaines sont incluses dans les éditions courantes. En revanche
`control_management_pack_access` vaut `DIAGNOSTIC+TUNING` : c'est **la valeur par défaut
sur Enterprise Edition**, et elle ouvre l'accès aux deux packs. Ouvert n'est pas utilisé,
mais une base où ils sont ouverts peut les utiliser sans que personne ne s'en aperçoive.

### Ce que le script ne fait pas

- **Il ne juge pas.** Aucun mot de conformité, aucun montant, aucun score. Un audit de
  licence se fait avec les scripts officiels Oracle et se discute avec Oracle ; ce script
  donne le point de départ d'une vérification contractuelle, sur votre base, en lecture
  seule.
- **Il ne voit qu'un conteneur à la fois.** La vue qui les verrait tous d'un coup,
  `CDB_FEATURE_USAGE_STATISTICS`, n'existe pas en 11g, et un compte sans grant dessus
  reçoit `ORA-00942` : c'était le cas du compte de lecture de test. Le script s'en passe
  et dit où il est.
- **Il ne lit aucune vue sous licence.** Ni `DBA_HIST_*`, ni ASH. Lire ce script ne crée
  aucune trace d'usage d'un pack.

### Vérifier que le script détecte

Ce sujet a une particularité : **l'anomalie ne se provoque pas à la demande**. Un usage
n'apparaît dans la vue qu'au prochain passage du job d'échantillonnage, jusqu'à une
semaine plus tard. C'est la leçon même du script, et il vaut mieux la vivre que la lire.

**Ce qui se vérifie tout de suite, sur une base multitenant :**

1. Lance le script dans une PDB. Note le `CONTENEUR COURANT` et le `DERNIER ECHANTILLON`.
2. Lance-le depuis `CDB$ROOT` (`sqlplus / as sysdba` y atterrit). Le conteneur a changé,
   **et la date d'échantillon aussi** : chaque conteneur porte sa propre mesure. Sur la
   base de test, la racine datait du 14/10 et la PDB du 19/10, pour la même base, avec
   29 fonctionnalités en usage côté racine contre 26 côté PDB et des dates de dernière
   détection différentes. Les trois fonctionnalités à licence séparée y étaient les mêmes :
   l'écart entre conteneurs peut être discret, ce qui le rend d'autant plus facile à
   manquer.
3. Lance-le avec un compte de lecture non privilégié dans la PDB : même résultat qu'au
   point 1, aucune erreur de privilège.

**Ce qui se vérifie en une semaine, sur une base de test seulement :**

```sql
CREATE TABLE t_demo_part (id NUMBER, d DATE)
PARTITION BY RANGE (d) (PARTITION p1 VALUES LESS THAN (MAXVALUE));
```

Au prochain échantillon, `Partitioning` apparaît en section 2 avec l'origine
`UTILISATEUR`. Supprime la table (`DROP TABLE t_demo_part PURGE;`) et attends encore un
échantillon : la ligne quitte la section 2, parce que `CURRENTLY_USED` repasse à `FALSE`,
mais la vue garde `DETECTED_USAGES` et `FIRST_USAGE_DATE`. C'est exactement ce qu'un audit
lit. Pour le voir :

```sql
SELECT name, currently_used, detected_usages, first_usage_date
FROM   dba_feature_usage_statistics
WHERE  name = 'Partitioning';
```

⚠️ **Sur une édition Enterprise, cette manipulation crée une vraie trace d'usage de
Partitioning.** Ne la fais que sur une base de test qui n'est soumise à aucun audit, ou sur
une Express Edition, où c'est inclus. Ce cycle d'une semaine n'a pas été exécuté pour ce
dépôt : seuls les trois passages ci-dessus l'ont été.

Deux pièges de manipulation : un commentaire `--` placé sur la même ligne qu'un `;`
empêche l'instruction de s'exécuter, et `sqlplus / as sysdba` se connecte dans `CDB$ROOT`,
où les données applicatives ne sont pas.

### Privilèges requis

| Section | Vue | Privilège |
|---|---|---|
| 1 | `V$VERSION`, `V$DATABASE`, `DBA_FEATURE_USAGE_STATISTICS` | `SELECT` sur `V_$VERSION`, `V_$DATABASE` et `DBA_FEATURE_USAGE_STATISTICS`, ou `SELECT_CATALOG_ROLE` |
| 2 | `DBA_FEATURE_USAGE_STATISTICS`, `V$VERSION` | idem |
| 3 | `V$OPTION`, `V$PARAMETER`, `V$LICENSE` | `SELECT` sur `V_$OPTION`, `V_$PARAMETER` et `V_$LICENSE`, ou `SELECT_CATALOG_ROLE` |

Aucune vue sous licence. Exécuté avec un compte de lecture non privilégié.

### Portée et limites

- **CDB / PDB : lance-le dans chaque PDB où vivent les données applicatives.**
  `DBA_FEATURE_USAGE_STATISTICS` ne montre que le conteneur courant, avec sa propre date
  d'échantillon. Depuis `CDB$ROOT` on obtient un résultat plausible et incomplet, et rien
  ne prévient : le script affiche le conteneur en tête pour cette raison.
- **Deux DBID dans la même vue.** Dans une PDB, la vue peut porter les lignes d'un
  ancien identifiant de base (clone, PDB d'amorçage), sans échantillon. Sur la base de
  test : 248 lignes pour chacun des deux DBID. Le script filtre sur `V$DATABASE.DBID`,
  sans quoi tous les compteurs de la section 1 doublent.
- **Le délai d'échantillonnage.** Une activation postérieure au dernier échantillon n'est
  pas visible. Un âge de quelques jours est normal ; un âge de plusieurs mois signale que
  le job interne ne tourne plus, et que la vue entière est périmée.
- **L'édition.** Sur Express et Personal Edition, la colonne `LECTURE` vaut `INCLUS DANS
  L EDITION` pour toutes les lignes. Le script ne distingue pas Standard Edition de ses
  variantes : il affiche le bandeau de `V$VERSION` et vous laisse le lire.
- **RAC : hors périmètre.** `V$LICENSE` est locale à l'instance (pic « depuis le démarrage
  de l'instance ») ; ce script ne consolide pas plusieurs nœuds.
- **Oracle 11g.** La ligne `CONTENEUR COURANT` rend `ORA-02003` : il n'y a pas de
  conteneurs, le reste du script s'exécute normalement.
- **Versions : ce qui est visé, ce qui est vérifié.** Écrit pour Oracle 11.2 et
  supérieur. Exécuté sur **Oracle 21c Express Edition 21.0.0.0.0**, base multitenant,
  depuis la PDB et depuis `CDB$ROOT`, en `SYSDBA` puis avec un compte de lecture non
  privilégié. Pas encore exécuté sur 11.2 ni sur 19c, ni sur une édition Enterprise :
  l'aperçu ci-dessus est fictif.

### Sources

Comportement d'Oracle : *Oracle Database 19c Reference*, chapitre 4.247
`DBA_FEATURE_USAGE_STATISTICS` (`CURRENTLY_USED` « usage détecté la dernière fois que le
système a vérifié », `LAST_SAMPLE_DATE`, `DETECTED_USAGES`, `FIRST_USAGE_DATE`), chapitre
8.105 `V$OPTION` (« installée »), chapitre 8.37 `V$LICENSE` (pic « depuis le démarrage de
l'instance »), chapitre 1.53 `CONTROL_MANAGEMENT_PACK_ACCESS` (valeurs, défaut
`DIAGNOSTIC+TUNING` sur Enterprise Edition, `NONE` ailleurs) ; *Oracle Database 19c
Licensing Information User Manual*, « Oracle Management Packs and Their Permitted
Features » (tout accès à la fonctionnalité Diagnostics Pack exige la licence). Les
droits d'une édition relèvent de la licence de cette édition et de votre contrat.

---

Nouveaux scripts régulièrement. Pour être prévenu,
**[suivez-moi sur LinkedIn](https://www.linkedin.com/in/omar-sall)**.

Je construis **Deynao**, la supervision continue des parcs Oracle on-premise : en lecture
seule, sans agent sur les serveurs de bases, aucun flux transmis à l'éditeur. En phase
d'évaluation, sur vos propres bases : [deynao.fr](https://deynao.fr)
