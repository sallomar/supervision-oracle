# Supervision Oracle : scripts de diagnostic

Scripts SQL de supervision et de diagnostic pour bases Oracle, commentés en français.
**SELECT uniquement**, sans agent à installer, sans vue des packs Diagnostics ou Tuning.

---

## À qui ça s'adresse

**DBA Oracle.** Un contrôle rapide et lisible, que vous pouvez relire avant de l'exécuter,
y compris sur une base dont vous héritez et que personne ne vous a documentée.

**Responsable d'applications.** Votre application tourne sur Oracle et vous en répondez, sans
être DBA. Ces scripts disent où regarder quand elle ralentit, se bloque ou s'arrête, et avec
quels mots en parler à votre DBA ou à votre prestataire.

**Consultant, ESN, infogérant.** Vous intervenez sur des bases clientes différentes chaque
semaine. Le même diagnostic, reproductible d'un client à l'autre, sans rien installer chez eux
et sans risque d'écart de licence.

**Exploitation et administration système.** Vous tenez une base Oracle sans DBA à temps plein,
et il faut quand même pouvoir répondre : est-ce que ça tient, et jusqu'à quand.

**DSI et responsables informatiques.** De quoi demander un état des lieux factuel à votre équipe
ou à votre prestataire, et comprendre la réponse.

Chaque script répond à **une** question d'exploitation, pas à toutes. Les requêtes sont
commentées ligne à ligne : elles s'apprennent en se lisant, avant de servir en production.

## Comment les utiliser

```sql
-- Depuis SQL*Plus, connecté à la base à diagnostiquer
@nom-du-script.sql
```

Trois garanties, valables pour tous les scripts de ce dépôt :

1. **Lecture seule.** Uniquement des `SELECT`. Aucun `DDL`, aucun `DML`, aucune modification de
   votre base. Vous pouvez les lire avant de les lancer, et vous devriez.
2. **Aucun pack sous licence.** Vues du dictionnaire et vues dynamiques `V$` standard. Ni
   `DBA_HIST_*`, ni `V$ACTIVE_SESSION_HISTORY`, ni aucune vue relevant du Diagnostics ou du
   Tuning Pack : un script de diagnostic ne doit jamais créer un écart de licence.
3. **Aucune donnée réelle.** Les exemples de sortie utilisent des noms fictifs
   (`ORCL`, `APP_PAIE`, `COMPTA`, `HR_ADMIN`).

## Droits requis

Un compte de lecture suffit. Chaque script indique en en-tête les vues qu'il interroge, afin que
vous puissiez accorder le strict nécessaire plutôt qu'un rôle `DBA`.

## Périmètre

Écrits pour des bases Oracle **single-instance**. RAC, ASM, Data Guard et GoldenGate ne sont
pas couverts.

Ce n'est pas une omission, c'est une limite assumée, et elle est tenue **dans le code** : quand
un script rencontre une situation qui relève de ce qu'il ne couvre pas, il l'affiche et la
signale hors périmètre, au lieu de rendre un résultat qu'il ne peut pas garantir. Un diagnostic
qui se tait vaut mieux qu'un diagnostic qui se trompe, et une réponse fausse coûte plus cher
qu'une absence de réponse.

## Compatibilité

Écrits pour **Oracle 11.2 et supérieur** : vues `V$` et vues du dictionnaire présentes de longue
date, sans fonction dépendante d'une version récente, sans vue de pack sous licence.

Chaque script indique en en-tête **les versions sur lesquelles il a réellement été exécuté**, et
les limites connues. Une compatibilité visée n'est pas une compatibilité vérifiée : ce dépôt ne
confond pas les deux, et vous dira toujours laquelle des deux vous avez sous les yeux.

## Structure

```
<domaine>/
  NN-question-traitee.sql      le script, commenté
  README.md                    la question, ce que la sortie signifie, les pièges
```

## Rester au courant

Un nouveau script est ajouté régulièrement, domaine après domaine, jusqu'à couvrir un bilan
de santé Oracle complet. Pour être prévenu :
**[suivez-moi sur LinkedIn](https://www.linkedin.com/in/omar-sall)**. J'y publie chaque
script avec le contexte, les pièges rencontrés et la manière de lire la sortie.

Si ces scripts vous servent, une **étoile** aide les suivants à les trouver, et me dit
lesquels méritent d'être maintenus en priorité.

## Auteur

**Omar SALL**, DBA Oracle, 10 ans et plus en production critique (collectivités territoriales).
Ces scripts sont ceux que j'utilise, écrits pour être relus avant d'être exécutés.

## Licence

MIT, voir [LICENSE](LICENSE). Utilisez, modifiez et redistribuez librement, y compris en
entreprise. Fournis sans garantie : relisez avant d'exécuter sur une base de production.
