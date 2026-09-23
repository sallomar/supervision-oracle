# Processus : combien avant que plus personne ne se connecte

*Un dossier de la série [supervision-oracle](../) : un script, une question.*

| Script | La question qu'il traite |
|---|---|
| [01-combien-avant-ora-00020.sql](01-combien-avant-ora-00020.sql) | À quelle distance de `ORA-00020` l'instance est-elle passée depuis son démarrage, et qui occupe les connexions |

---

## 01. Combien avant ORA-00020

`01-combien-avant-ora-00020.sql` répond à une question que personne ne pose tant que la
base répond : de combien est-on passé à côté de l'arrêt des connexions, et qui tient les
places.

### Pourquoi ça compte

`ORA-00020: maximum number of processes exceeded` n'est pas une erreur applicative. C'est
la base qui refuse toute nouvelle connexion, parce que le paramètre `PROCESSES` (« le
nombre maximal de processus utilisateur du système d'exploitation qui peuvent se
connecter simultanément à Oracle ») est atteint. Les sessions déjà ouvertes continuent ;
tout ce qui essaie d'entrer est refusé, application comme administrateur. Sa jumelle
`ORA-00018` fait la même chose pour `SESSIONS`.

Le réflexe habituel est de regarder l'occupation **du moment**. C'est le mauvais chiffre :
l'incident se produit au pic, et le pic n'est presque jamais le moment où l'on regarde.
Oracle garde pourtant ce pic. `V$RESOURCE_LIMIT` expose, pour chaque ressource, la
consommation en cours et la **consommation maximale atteinte depuis le dernier démarrage
de l'instance** (`MAX_UTILIZATION`). Un script lancé une fois ne voit que l'instant ; le
pic est la mémoire qu'Oracle tient à sa place. C'est donc sur lui que porte le verdict.

| Niveau | Pic depuis le démarrage | Ce que ça veut dire |
|---|---|---|
| `CRITIQUE` | plus de 90 % de la limite | L'instance est déjà passée à quelques connexions de l'arrêt. La prochaine pointe peut être la bonne. |
| `ATTENTION` | plus de 70 % | Pas encore un incident : la marge existe, mais elle se mesure, elle ne se suppose pas. |
| `OK` | 70 % ou moins | La limite n'est pas le sujet. Si les connexions sont refusées, la cause est ailleurs. |

Ce sont les paliers d'une supervision continue, qui juge l'occupation instantanée parce
qu'elle la relève sans arrêt. Appliqués au pic, ils disent la même chose à un script qui
ne passe qu'une fois.

**Trois faits qui changent la lecture :**

- **Le pic repart à zéro au redémarrage.** Un `MAX_UTILIZATION` bas sur une instance
  relancée hier ne prouve rien. Le script affiche la date de démarrage pour cette raison :
  « pic depuis le démarrage » n'a de sens que si l'on sait de quand date le démarrage.
- **`SESSIONS` est dérivé de `PROCESSES`, et la formule dépend de la version.** La
  documentation 19c donne `(1.5 * PROCESSES) + 22`. Sur la base 21c de test, avec
  `PROCESSES = 1600` et `SESSIONS` laissé à sa valeur par défaut (`ISDEFAULT = TRUE`), la
  valeur dérivée est 2 440, pas 2 422. Ne calcule pas la limite : lis-la. Et une valeur
  de `SESSIONS` fixée sous le défaut est ignorée par Oracle, qui garde le défaut.
- **En multitenant, la limite est celle de l'instance, toutes PDB comprises.** Quand elle
  est atteinte, plus personne ne se connecte à **aucune** PDB. Une PDB qui fuit ferme donc
  la porte à toutes les autres ; on peut la plafonner avec son propre `SESSIONS`.

### Ce que le script vérifie

1. **La distance à la limite.** Pour `processes` et `sessions` : occupation en cours, pic
   depuis le démarrage, limite, les deux pourcentages, et le verdict sur le pic. La date
   de démarrage de l'instance est affichée juste au-dessus.
2. **Qui occupe les connexions.** Les dix premiers groupes utilisateur / programme /
   machine par nombre de sessions, avec le nombre de sessions inactives et l'ancienneté de
   la plus ancienne. C'est là qu'on identifie un pool surdimensionné ou une application
   qui n'a jamais fermé ce qu'elle a ouvert.

⚠️ **Les deux sections ne parlent pas du même moment, et c'est la limite principale de ce
script.** La section 1 est rétrospective : elle rapporte un pic qui peut dater de trois
semaines. La section 2 est instantanée : elle montre qui est connecté maintenant. Si le
pic est ancien, la section 2 **ne dit rien de ses responsables** : elle décrit la
situation ordinaire, ce qui reste utile (un pool surdimensionné l'est en permanence) mais
ne désigne personne. Pour relier les deux, il faut soit lancer le script pendant la
pointe, soit reconnaître dans la section 2 un consommateur structurellement trop gros.

### Aperçu de la sortie

```
SQL> @01-combien-avant-ora-00020.sql

=========================================================================
 COMBIEN AVANT ORA-00020  ==  lecture seule, aucune modification
=========================================================================

=== SECTION 1 : distance a la limite, en cours et pic depuis le demarrage

                                       DEPUIS
INSTANCE         DEMARREE LE          (JOURS)
---------------- ------------------- --------
ORCL             12/08/2026 04:12:07     42.1

1 ligne selectionnee.

           ERREUR          EN  PIC DEPUIS             % EN    % DU VERDICT
RESSOURCE  SI PLEIN     COURS   DEMARRAGE   LIMITE   COURS     PIC (SUR LE PIC)
---------- --------- -------- ----------- -------- ------- ------- ---------------------------
processes  ORA-00020      212         287      300    70.7    95.7 CRITIQUE : pic > 90 %
sessions   ORA-00018      241         322      472    51.1    68.2 OK

2 lignes selectionnees.


=== SECTION 2 : qui occupe les connexions, par utilisateur et programme ==
 Sessions utilisateur seulement : les processus d arriere-plan occupent
 aussi des slots. Depuis une PDB, seules les sessions de la PDB sont vues.

                                                                                                      INACTIVE LA
                                                                                              DONT  PLUS ANCIENNE
UTILISATEUR          PROGRAMME                      MACHINE                    SESSIONS  INACTIVES      (MINUTES)
-------------------- ------------------------------ ------------------------- --------- ---------- --------------
APP_PAIE             JDBC Thin Client               appserv01                        72         69           1437
APP_PAIE             JDBC Thin Client               appserv02                        64         61           1435
BATCH_USER           sqlplus@batch01 (TNS V1-V3)    batch01                          14          2              8
COMPTA               w3wp.exe                       WEBCOMPTA01                       9          9            212
HR_ADMIN             SQL Developer                  PC-HR-07                          3          3             54
SYS                  sqlplus@dbsrv01 (TNS V1-V3)    dbsrv01                           1          0

6 lignes selectionnees.


=========================================================================
 Fin. Aucune modification n a ete faite sur cette base.
=========================================================================
```

**Lecture de la section 1.** Au moment où le script passe, l'instance est à 70,7 % de sa
limite de processus : rien d'alarmant. Mais depuis son démarrage, il y a 42 jours, elle
est montée à 287 sur 300. **Treize connexions avant l'arrêt**, et personne ne l'a vu,
parce que personne ne regardait à ce moment-là. La ligne `sessions` est à `OK` : dans cet
exemple, c'est bien `PROCESSES` qui est la limite courte, pas `SESSIONS`.

**Lecture de la section 2.** Les deux serveurs d'application de la paie tiennent 136
sessions, dont 130 inactives depuis presque 24 heures : ce sont des pools de connexions
dimensionnés à une soixantaine de connexions chacun, et gardés ouverts en permanence.
Ce n'est pas une fuite, c'est un réglage. Le levier est la taille du pool, avec l'équipe
applicative, pas un `KILL SESSION`. La colonne d'ancienneté se lit comme dans
[01-qui-bloque-qui.sql](../verrous/01-qui-bloque-qui.sql) : sur une session `INACTIVE`,
`LAST_CALL_ET` est le temps écoulé depuis son dernier appel.

**Depuis une PDB**, la section 1 ne peut pas répondre, et elle le dit au lieu de se vider :

```
           ERREUR          EN  PIC DEPUIS             % EN    % DU VERDICT
RESSOURCE  SI PLEIN     COURS   DEMARRAGE   LIMITE   COURS     PIC (SUR LE PIC)
---------- --------- -------- ----------- -------- ------- ------- ---------------------------
processes  ORA-00020                           300                 NON VISIBLE : voir CDB$ROOT
sessions   ORA-00018                           472                 NON VISIBLE : voir CDB$ROOT
```

La limite reste visible (elle vient de `V$PARAMETER`), l'occupation et le pic non. Voir
« Portée et limites ».

### Ce que le script ne fait pas

- **Il ne dit pas quand le pic a eu lieu.** `V$RESOURCE_LIMIT` garde le maximum, pas sa
  date. L'historique existe dans `DBA_HIST_RESOURCE_LIMIT`, qui prend des instantanés de
  cette vue, mais les vues `DBA_HIST_` relèvent du Diagnostics Pack, payant sur Enterprise
  Edition. Ce script s'en passe, comme tous ceux de ce dépôt.
- **Il ne libère rien.** Tuer des sessions inactives ne règle pas un pool surdimensionné :
  le pool les rouvrira. Augmenter `PROCESSES` est une décision de fenêtre de maintenance,
  le paramètre n'est pas modifiable à chaud et exige un redémarrage de l'instance ; à
  valider avec la mémoire disponible sur le serveur, chaque processus en consomme.

### Vérifier que le script détecte

Sur une base de **test** uniquement. L'anomalie se provoque sans risque : il suffit
d'ouvrir des sessions et de les garder ouvertes.

**Étape 1, combien de sessions ouvrir ?** Lance le script depuis `CDB$ROOT` (ou sur une
base non-CDB) et lis la ligne `processes`. Le nombre de sessions à ouvrir n'est pas un
nombre fixe : il faut **dépasser le pic déjà atteint**, donc ouvrir plus que
`PIC DEPUIS DEMARRAGE` moins `EN COURS`, avec de la marge. Une base démarrée depuis
longtemps a souvent un pic bien au-dessus de son occupation courante, et un nombre trop
petit ne ferait rien bouger, ce qui ressemblerait à un script qui ne détecte rien.

**Étape 2, ouvrir les sessions**, dans un autre terminal. Remplace `40` par le nombre
calculé à l'étape 1.

```
# Linux / Unix
for i in $(seq 1 40); do
  echo "exec dbms_session.sleep(180)" | sqlplus -S app_user/motdepasse@ORCL &
done
```

```
REM Windows, invite cmd
echo exec dbms_session.sleep(180); > %TEMP%\attente.sql
echo exit >> %TEMP%\attente.sql
for /L %i in (1,1,40) do start /b sqlplus -S app_user/motdepasse@ORCL @%TEMP%\attente.sql
```

`DBMS_SESSION.SLEEP` n'est qu'une commodité pour que les sessions se ferment seules. Sur
une version où il n'existe pas, `DBMS_LOCK.SLEEP` fait la même chose si ton compte a le
droit de l'exécuter ; à défaut, une fenêtre SQL\*Plus laissée ouverte par session convient.

**Étape 3, regarder pendant.** Relance le script tant que les sessions vivent. `EN COURS`
a augmenté d'autant, `PIC DEPUIS DEMARRAGE` a bougé, et la section 2 montre le compte
utilisé avec toutes ses sessions.

**Étape 4, regarder après.** Attends la fin des sessions et relance : `EN COURS` est
revenu à sa valeur de départ, et **le pic est resté**. C'est exactement ce que le script
mesure, et ce qu'aucune lecture instantanée ne dira jamais.

Exemple mesuré sur la base de test : avant, 90 en cours pour un pic à 115 ; pendant les 40
sessions, 131 en cours et le pic monté à **132** ; après leur fermeture, 91 en cours et le
pic toujours à **132**. Noter au passage que pendant la provocation, le pic (132) était
déjà **au-dessus** de l'occupation du moment (131) : le vrai maximum était passé avant même
qu'on regarde.

**Remise en état** : rien à défaire, les sessions se ferment seules. Vérifier :

```sql
SELECT COUNT(*) FROM v$session WHERE username = 'APP_USER';   -- doit rendre 0
```

Trois pièges de manipulation : un commentaire `--` placé sur la même ligne qu'un `;`
empêche l'instruction de s'exécuter ; `sqlplus / as sysdba` se connecte dans `CDB$ROOT`
(pour ce script c'est le bon endroit, et pour ouvrir les sessions de test le conteneur
n'a pas d'importance, la limite est la même pour tous) ; et sous Windows, coller un bloc
contenant une ligne `exit` dans l'invite `cmd` **ferme la fenêtre** au lieu d'écrire le
fichier, d'où les deux `echo` séparés ci-dessus.

### Privilèges requis

| Section | Vue | Privilège |
|---|---|---|
| 1 | `V$INSTANCE`, `V$RESOURCE_LIMIT`, `V$PARAMETER` | `SELECT` sur `V_$INSTANCE`, `V_$RESOURCE_LIMIT` et `V_$PARAMETER`, ou `SELECT_CATALOG_ROLE` |
| 2 | `V$SESSION` | `SELECT` sur `V_$SESSION`, ou `SELECT_CATALOG_ROLE` |

Aucune vue sous licence. Exécuté avec un compte de lecture non privilégié.

⚠️ **Sur une base multitenant, ces privilèges ne suffisent pas à eux seuls : le compte doit
être connecté à `CDB$ROOT`.** Un compte de supervision local à une PDB a beau avoir tous
les droits sur `V$RESOURCE_LIMIT`, il n'en verra aucune ligne : la section 1 affichera
`NON VISIBLE : voir CDB$ROOT`. À prévoir avant de donner l'accès à l'équipe. Sur une base
non-CDB, la question ne se pose pas.

### Portée et limites

- **CDB / PDB : lance-le depuis `CDB$ROOT`.** C'est l'inverse des scripts du dossier
  `verrous/`, et la raison est mesurée : sur la base de test, `V$RESOURCE_LIMIT` ne rend
  **aucune ligne** depuis une PDB, toutes ses lignes portant `CON_ID = 1`. La section 1 y
  affiche la limite (qui, elle, se lit dans la PDB) et le verdict `NON VISIBLE : voir
  CDB$ROOT` ; la section 2 n'y compte que les sessions de la PDB, alors que la limite est
  celle de l'instance entière. Une section vide aurait fait conclure « rien à signaler » :
  le script préfère dire qu'il ne voit pas.
- **RAC : hors périmètre.** `V$RESOURCE_LIMIT` décrit l'instance courante (sa vue
  d'historique la photographie par `INSTANCE_NUMBER`). Chaque nœud a sa limite et son pic ;
  ce script ne les additionne pas.
- **Les processus d'arrière-plan comptent.** La limite `PROCESSES` s'applique à tous les
  processus de l'instance, `V$PROCESS` les liste tous. La section 2 ne montre que les
  sessions utilisateur : l'écart avec `EN COURS` est l'arrière-plan et les processus sans
  session utilisateur. Sur une petite base, cet écart est la majorité du total.
- **Versions : ce qui est visé, ce qui est vérifié.** Écrit pour Oracle 11.2 et supérieur :
  `V$RESOURCE_LIMIT`, `V$INSTANCE`, `V$PARAMETER` et `V$SESSION` sont servies de longue
  date, et le script n'utilise ni `FETCH FIRST`, ni `CON_ID`, ni `SYS_CONTEXT` sur le
  conteneur. Exécuté sur **Oracle 21c Express Edition 21.0.0.0.0**, base multitenant,
  depuis `CDB$ROOT` et depuis la PDB, en `SYSDBA` puis avec un compte de lecture non
  privilégié, avec l'anomalie provoquée (40 sessions ouvertes : le pic est passé de 115 à
  132, puis il est resté à 132 après leur fermeture). Pas encore exécuté sur 11.2 ni sur 19c.

### Sources

Comportement d'Oracle : *Oracle Database 19c Reference*, chapitre 8.166 `V$RESOURCE_LIMIT`
(`MAX_UTILIZATION` « depuis le dernier démarrage de l'instance », `LIMIT_VALUE`, table
8-5), chapitre 1.272 `PROCESSES` (« Modifiable : No », `SESSIONS` et `TRANSACTIONS` en
dérivent), chapitre 1.307 `SESSIONS` (valeur dérivée, valeur sous le défaut ignorée),
chapitre 5.37 `DBA_HIST_RESOURCE_LIMIT`, chapitre 8.127 `V$PROCESS` ;
*Oracle Database 19c Multitenant Administrator's Guide*, § 13.2.1.2 « Session Limits in a
CDB » ; *Oracle Database 19c Licensing Information User Manual*, table 1-15, Oracle
Diagnostics Pack (vues `DBA_HIST_`).

---

Nouveaux scripts régulièrement. Pour être prévenu,
**[suivez-moi sur LinkedIn](https://www.linkedin.com/in/omar-sall)**.

Je construis **Deynao**, la supervision continue des parcs Oracle on-premise : en lecture
seule, sans agent sur les serveurs de bases, aucun flux transmis à l'éditeur. En phase
d'évaluation, sur vos propres bases : [deynao.fr](https://deynao.fr)
