-- ===========================================================================
-- SCRIPT        : 01-options-activees-sans-le-savoir.sql
-- OBJECTIF      : Quelles fonctionnalites soumises a licence separee ont ete
--                 OBSERVEES en usage sur cette base, depuis quand, et si c est
--                 Oracle ou vous qui les avez declenchees. Point de depart d une
--                 verification contractuelle.
-- CE QUE CE     : un audit. Un audit de licence se fait avec les scripts
-- N EST PAS       officiels Oracle et se discute avec Oracle. Seul votre contrat
--                 determine vos droits d utilisation. Ce script ne qualifie
--                 jamais une conformite et ne chiffre jamais un montant.
-- VUES          : V$VERSION, V$DATABASE, DBA_FEATURE_USAGE_STATISTICS (1 et 2),
--                 V$OPTION, V$PARAMETER, V$LICENSE (section 3)
-- PRIVILEGES    : SELECT sur V_$VERSION, V_$DATABASE, V_$OPTION, V_$PARAMETER,
--                 V_$LICENSE et sur DBA_FEATURE_USAGE_STATISTICS (ou
--                 SELECT_CATALOG_ROLE). Aucune vue sous licence.
-- LECTURE SEULE : que des SELECT. Aucun DDL, aucun DML, aucun ALTER.
-- ECRIT POUR    : Oracle 11.2 et superieur. Sur 11g, la ligne CONTENEUR rend
--                 ORA-02003 (pas de conteneurs) : c est attendu, ignore-la.
-- EXECUTE SUR   : Oracle 21c Express Edition 21.0.0.0.0, base multitenant,
--                 depuis une PDB et depuis CDB$ROOT, en SYSDBA puis avec un
--                 compte de lecture non privilegie. Pas encore execute sur
--                 11.2 ni sur 19c.
-- CDB           : DBA_FEATURE_USAGE_STATISTICS ne montre que le CONTENEUR
--                 COURANT, avec sa propre date d echantillon. Lance-le DANS
--                 chaque PDB ou vivent les donnees applicatives : depuis
--                 CDB$ROOT tu ne vois que la racine, et rien ne te previent.
-- PERIMETRE     : bases SINGLE-INSTANCE.
-- A SAVOIR      : CURRENTLY_USED = usage detecte AU DERNIER ECHANTILLON. Le job
--                 d echantillonnage passe environ une fois par semaine : une
--                 activation d hier n est pas encore visible. L edition compte :
--                 en Express et en Personal Edition, les fonctionnalites
--                 presentes sont INCLUSES dans la licence de l edition.
-- LA LISTE      : ce qui compte comme « licence separee » suit le manuel de
--                 licence Oracle 19c, revision E94254-18 d avril 2020. Spatial
--                 and Graph, Machine Learning (ex Advanced Analytics), Oracle
--                 Text, Privilege Analysis et Flashback Data Archive de base y
--                 sont INCLUS dans toutes les editions : le script ne les
--                 signale pas. Multitenant : jusqu a 3 PDB utilisateur par CDB
--                 sans licence (manuel 19c, table 1-2, p. 1-4) ; au-dela, option.
--                 Les paliers liberes apres cette revision (ex. In-Memory) n y
--                 sont pas : le manuel de VOTRE version fait foi.
-- USAGE         : SQL> @01-options-activees-sans-le-savoir.sql
--
-- Limites connues (conteneurs, delai d echantillon, edition) : README du dossier.
-- ===========================================================================

SET DEFINE OFF
SET LINESIZE 240
SET PAGESIZE 100
SET FEEDBACK ON
SET TRIMSPOOL ON
SET TAB OFF
CLEAR COLUMNS

PROMPT
PROMPT =========================================================================
PROMPT  OPTIONS ACTIVEES SANS LE SAVOIR  ==  lecture seule, pas un audit
PROMPT =========================================================================
PROMPT
PROMPT === SECTION 1 : edition, conteneur, et fraicheur de la vue ==============
PROMPT  Rien de ce qui suit ne se lit sans ces trois informations.
PROMPT

COLUMN edition_oracle FORMAT A72 HEADING "EDITION ET VERSION (V$VERSION)"

SELECT banner AS edition_oracle
FROM   v$version
WHERE  UPPER(banner) LIKE 'ORACLE DATABASE%'
AND    ROWNUM = 1;

COLUMN nom_base FORMAT A12 HEADING "BASE"
COLUMN conteneur FORMAT A30 HEADING "CONTENEUR COURANT"

SELECT name AS nom_base FROM v$database;

PROMPT  (sur Oracle 11g la ligne suivante rend ORA-02003 : pas de conteneurs, attendu)
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS conteneur FROM dual;

COLUMN dernier_echantillon FORMAT A19      HEADING "DERNIER ECHANTILLON|DE LA VUE"
COLUMN age_jours           FORMAT 99990.0  HEADING "AGE|(JOURS)"
COLUMN nb_lignes           FORMAT 9999999  HEADING "LIGNES|SUIVIES"
COLUMN nb_en_usage         FORMAT 9999999  HEADING "EN USAGE|(TOTAL)"
COLUMN nb_payantes         FORMAT 99999999999999 HEADING "EN USAGE|(LIC. SEPAREE)"

-- La vue est alimentee par echantillons : une activation posterieure a cette
-- date n est pas encore dedans. Un echantillon vieux de 7 jours est normal.
SELECT
    TO_CHAR(MAX(last_sample_date), 'DD/MM/YYYY HH24:MI:SS')   AS dernier_echantillon,
    ROUND(SYSDATE - MAX(last_sample_date), 1)                 AS age_jours,
    COUNT(*)                                                  AS nb_lignes,
    SUM(CASE WHEN f.currently_used = 'TRUE' THEN 1 ELSE 0 END) AS nb_en_usage,
    SUM(CASE WHEN f.currently_used = 'TRUE'
              AND ( REGEXP_LIKE(LOWER(f.name),
                      'partitioning|olap|real application cluster|advanced compression|advanced security|label security|database vault|active data guard|in-memory column store|multitenant|real application testing|diagnostics pack|tuning pack')
                 OR REGEXP_LIKE(LOWER(f.name),
                      'sql tuning advisor|sql access advisor|database replay|sqltune|oracle database in-memory|heat map|automatic data optimization|hybrid columnar compression|advanced index compression|data redaction|encrypted tablespace|backup encryption') )
             THEN 1 ELSE 0 END)                               AS nb_payantes
FROM v$database d, dba_feature_usage_statistics f
WHERE f.dbid = d.dbid;

PROMPT
PROMPT === SECTION 2 : fonctionnalites a licence separee OBSERVEES en usage ====
PROMPT  Dans CE conteneur, au dernier echantillon. Section vide : aucune
PROMPT  fonctionnalite de la liste n y etait detectee en usage a cette date.
PROMPT

COLUMN fonctionnalite FORMAT A48      HEADING "FONCTIONNALITE (DBA_FEATURE_USAGE_STATISTICS)"
COLUMN detections     FORMAT 9999999  HEADING "DETEC-|TIONS"
COLUMN premiere       FORMAT A10      HEADING "PREMIERE|DETECTION"
COLUMN derniere       FORMAT A10      HEADING "DERNIERE|DETECTION"
COLUMN origine        FORMAT A11      HEADING "ORIGINE"
COLUMN lecture        FORMAT A24      HEADING "LECTURE"

-- Liste des fonctionnalites a licence separee : manuel 19c, revision avril 2020.
-- ORIGINE : SYSTEME = declenche par Oracle lui-meme (suffixe (system), taches de
-- maintenance automatique, objets du dictionnaire). LECTURE : jamais un verdict
-- de conformite, un point de depart. Sur Express/Personal tout est inclus.
SELECT
    fonctionnalite,
    detections,
    premiere,
    derniere,
    origine,
    CASE
        WHEN edition_gratuite > 0                        THEN 'INCLUS DANS L EDITION'
        WHEN LOWER(fonctionnalite) LIKE '%multitenant%'  THEN 'SEUIL 3 PDB, MANUEL 19C'
        WHEN origine = 'SYSTEME'                         THEN 'USAGE INTERNE ORACLE'
        ELSE                                                  'A RAPPROCHER DU CONTRAT'
    END AS lecture
FROM (
    SELECT
        f.name                                      AS fonctionnalite,
        f.detected_usages                           AS detections,
        TO_CHAR(f.first_usage_date, 'DD/MM/YYYY')   AS premiere,
        TO_CHAR(f.last_usage_date,  'DD/MM/YYYY')   AS derniere,
        CASE
            WHEN LOWER(f.name) LIKE '%(system)%'
              OR REGEXP_LIKE(LOWER(f.name),
                   'automatic maintenance|auto sql tuning|auto optimizer|automatic sql tuning|auto space advisor|automatic segment advisor|automatic workload repository')
              OR REGEXP_LIKE(LOWER(f.feature_info),
                   'dictionary|sys\.|system\.|mdsys\.|ctxsys\.|xdb\.|audsys\.|wmsys\.|ordsys\.|olapsys\.|appqossys\.|dbsnmp\.|gsmadmin_internal\.')
            THEN 'SYSTEME'
            ELSE 'UTILISATEUR'
        END                                         AS origine,
        (SELECT COUNT(*) FROM v$version
         WHERE banner LIKE '%Express Edition%'
            OR banner LIKE '%Personal Edition%')    AS edition_gratuite
    FROM v$database d, dba_feature_usage_statistics f
    WHERE f.dbid = d.dbid
    AND   f.currently_used = 'TRUE'
    AND   ( REGEXP_LIKE(LOWER(f.name),
              'partitioning|olap|real application cluster|advanced compression|advanced security|label security|database vault|active data guard|in-memory column store|multitenant|real application testing|diagnostics pack|tuning pack')
         OR REGEXP_LIKE(LOWER(f.name),
              'sql tuning advisor|sql access advisor|database replay|sqltune|oracle database in-memory|heat map|automatic data optimization|hybrid columnar compression|advanced index compression|data redaction|encrypted tablespace|backup encryption') )
)
ORDER BY CASE origine WHEN 'UTILISATEUR' THEN 1 ELSE 2 END, fonctionnalite;

PROMPT
PROMPT === SECTION 3 : installe et configure, ce qui N EST PAS un usage =========
PROMPT  V$OPTION dit ce que les binaires contiennent, pas ce qui sert. Un pack
PROMPT  ouvert est une configuration, pas un usage : l usage se lit en section 2.
PROMPT

COLUMN option_oracle FORMAT A30 HEADING "OPTION (V$OPTION)"
COLUMN etat_option   FORMAT A34 HEADING "ETAT"

SELECT
    parameter                             AS option_oracle,
    'INSTALLEE, PAS FORCEMENT UTILISEE'   AS etat_option
FROM v$option
WHERE value = 'TRUE'
AND   parameter IN ('Partitioning', 'OLAP', 'Real Application Clusters',
                    'Real Application Testing', 'Advanced Compression',
                    'Advanced Security', 'Label Security', 'Database Vault',
                    'Active Data Guard', 'In-Memory Column Store', 'Multitenant')
ORDER BY parameter;

COLUMN parametre    FORMAT A31 HEADING "PARAMETRE"
COLUMN valeur       FORMAT A18 HEADING "VALEUR"
COLUMN lecture_pack FORMAT A36 HEADING "LECTURE"

SELECT
    name  AS parametre,
    value AS valeur,
    CASE
        WHEN UPPER(value) = 'NONE'           THEN 'AUCUN PACK OUVERT'
        WHEN UPPER(value) LIKE '%TUNING%'    THEN 'DIAGNOSTICS ET TUNING PACK OUVERTS'
        WHEN UPPER(value) LIKE '%DIAGNOSTIC%' THEN 'DIAGNOSTICS PACK OUVERT'
        ELSE                                      'VALEUR NON RECONNUE'
    END   AS lecture_pack
FROM v$parameter
WHERE name = 'control_management_pack_access';

COLUMN plafond_sessions FORMAT A24     HEADING "PLAFOND SESSIONS|(SESSIONS_MAX)"
COLUMN pic_sessions     FORMAT 9999999999 HEADING "PIC DEPUIS|DEMARRAGE"
COLUMN plafond_users    FORMAT A24     HEADING "PLAFOND UTILISATEURS|NOMMES (USERS_MAX)"

SELECT
    CASE WHEN NVL(sessions_max, 0) = 0 THEN 'AUCUNE LIMITE CONFIGUREE'
         ELSE TO_CHAR(sessions_max) END   AS plafond_sessions,
    sessions_highwater                    AS pic_sessions,
    CASE WHEN NVL(users_max, 0) = 0    THEN 'AUCUNE LIMITE CONFIGUREE'
         ELSE TO_CHAR(users_max) END      AS plafond_users
FROM v$license;

PROMPT
PROMPT =========================================================================
PROMPT  Fin. Aucune modification n a ete faite sur cette base.
PROMPT  Ceci n est pas un audit : seul votre contrat Oracle determine vos droits.
PROMPT =========================================================================
PROMPT

CLEAR COLUMNS
