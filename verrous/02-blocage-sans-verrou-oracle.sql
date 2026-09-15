-- ===========================================================================
-- SCRIPT        : 02-blocage-sans-verrou-oracle.sql
-- OBJECTIF      : L application est bloquee : y a-t-il seulement un verrou
--                 Oracle ? Montre les verrous applicatifs VISIBLES (DBMS_LOCK,
--                 type UL) puis decouvre les tables de verrou logique
--                 Liquibase, invisibles de toute vue de verrouillage.
-- VUES          : V$LOCK et V$SESSION (section 1), ALL_TABLES (sections 2 et 3)
-- PRIVILEGES    : SELECT sur V_$LOCK et V_$SESSION (ou SELECT_CATALOG_ROLE).
--                 Les sections 2 et 3 ne montrent que les tables ACCESSIBLES
--                 au compte connecte : une table existante mais non accordee
--                 n apparait pas (demander un GRANT SELECT dessus).
-- LECTURE SEULE : que des SELECT. La section 3 GENERE une requete a lancer,
--                 elle ne lit jamais une table applicative d elle-meme.
-- ECRIT POUR    : Oracle 11.2 et superieur.
-- EXECUTE SUR   : Oracle 21c Express Edition 21.0.0.0.0, base multitenant,
--                 depuis une PDB et depuis CDB$ROOT, en SYSDBA puis avec un
--                 compte de lecture non privilegie. Pas encore execute sur
--                 11.2 ni sur 19c.
-- CDB           : lance-le DANS la PDB : les tables applicatives ne sont pas
--                 visibles depuis CDB$ROOT (section 2 vide, c est attendu).
-- PERIMETRE     : bases SINGLE-INSTANCE. En RAC, V$LOCK est locale au noeud :
--                 un verrou UL tenu ailleurs n apparait pas ici.
-- A SAVOIR      : un verrou logique est une LIGNE DE TABLE. Il survit au
--                 redemarrage de l instance et ne figure dans aucune vue de
--                 verrouillage : seule sa table le montre.
-- USAGE         : SQL> @02-blocage-sans-verrou-oracle.sql
--
-- Limites connues (RAC, CDB/PDB, fuseau JVM, droits) : README du dossier.
-- ===========================================================================

SET DEFINE OFF
SET LINESIZE 240
SET PAGESIZE 100
SET FEEDBACK ON
SET TRIMSPOOL ON
CLEAR COLUMNS

PROMPT
PROMPT =========================================================================
PROMPT  BLOCAGE SANS VERROU ORACLE  ==  lecture seule, aucune modification
PROMPT =========================================================================
PROMPT
PROMPT === SECTION 1 : verrous applicatifs visibles (DBMS_LOCK, type UL) ======
PROMPT

COLUMN etat_verrou    FORMAT A8      HEADING "ETAT"
COLUMN sid_verrou     FORMAT 99999   HEADING "SID"
COLUMN util_verrou    FORMAT A18     HEADING "UTILISATEUR"
COLUMN statut_verrou  FORMAT A9      HEADING "STATUT"
COLUMN id_applicatif  FORMAT 9999999999 HEADING "ID1|APPLICATIF"
COLUMN mode_verrou    FORMAT A13     HEADING "MODE"
COLUMN age_minutes    FORMAT 9999999 HEADING "AGE|MINUTES"

SELECT
    CASE WHEN l.lmode > 0 THEN 'DETIENT' ELSE 'ATTEND' END AS etat_verrou,
    l.sid                                    AS sid_verrou,
    NVL(s.username, '(session inconnue)')    AS util_verrou,
    NVL(s.status, '?')                       AS statut_verrou,
    l.id1                                    AS id_applicatif,
    CASE (CASE WHEN l.lmode > 0 THEN l.lmode ELSE l.request END)
        WHEN 1 THEN 'Null'
        WHEN 2 THEN 'Row-S (SS)'
        WHEN 3 THEN 'Row-X (SX)'
        WHEN 4 THEN 'Share'
        WHEN 5 THEN 'S/Row-X (SSX)'
        WHEN 6 THEN 'Exclusive'
        ELSE TO_CHAR(CASE WHEN l.lmode > 0 THEN l.lmode ELSE l.request END)
    END                                      AS mode_verrou,
    FLOOR(l.ctime / 60)                      AS age_minutes
FROM v$lock l
LEFT JOIN v$session s
  ON s.sid = l.sid
WHERE l.type = 'UL'
ORDER BY l.id1, etat_verrou;

PROMPT
PROMPT === SECTION 2 : tables de verrou logique Liquibase accessibles =========
PROMPT  Un verrou logique ne se voit que dans SA table. Section vide : aucune
PROMPT  table DATABASECHANGELOGLOCK accessible a ce compte.
PROMPT

COLUMN prop_table   FORMAT A25  HEADING "PROPRIETAIRE"
COLUMN nom_table    FORMAT A25  HEADING "TABLE"

SELECT owner       AS prop_table,
       table_name  AS nom_table
FROM all_tables
WHERE table_name = 'DATABASECHANGELOGLOCK'
ORDER BY owner;

PROMPT
PROMPT === SECTION 3 : requete a lancer, generee par table trouvee ============
PROMPT  A copier-coller telle quelle. Le script ne lit jamais une table
PROMPT  applicative de lui-meme : la decision de la lire t appartient.
PROMPT

SET HEADING OFF

COLUMN prop_genere   NOPRINT
COLUMN ordre_ligne   NOPRINT
COLUMN ligne_generee FORMAT A110

-- Seuils du verdict genere : plus de 30 min = WARNING, plus de 2 h = CRITICAL.
-- A adapter a la duree normale des migrations de l application.
-- LOCKEDBY est un VARCHAR2(255) : la requete le borne elle-meme, sinon la
-- sortie deborde. Le format vit dans le SELECT pour rester lisible ailleurs
-- que dans SQL*Plus (SQL Developer, DBeaver... n ont pas de directive COLUMN).
SELECT
    t.owner                                  AS prop_genere,
    g.ordre_ligne                            AS ordre_ligne,
    CASE g.ordre_ligne
        WHEN 1 THEN '-- ' || t.owner || '.DATABASECHANGELOGLOCK :'
        WHEN 2 THEN 'SELECT id,'
        WHEN 3 THEN '       locked,'
        WHEN 4 THEN '       TO_CHAR(lockgranted, ''DD/MM/YYYY HH24:MI:SS'') AS pose_le,'
        WHEN 5 THEN '       CAST(lockedby AS VARCHAR2(30)) AS pose_par,'
        WHEN 6 THEN '       CASE WHEN locked = 0 THEN ''OK'''
        WHEN 7 THEN '            WHEN lockgranted IS NULL THEN ''A CONTROLER : verrou pose sans date'''
        WHEN 8 THEN '            WHEN lockgranted < SYSDATE - 2/24 THEN ''CRITICAL : pose depuis plus de 2 h'''
        WHEN 9 THEN '            WHEN lockgranted < SYSDATE - 30/1440 THEN ''WARNING : pose depuis plus de 30 min'''
        WHEN 10 THEN '            ELSE ''OK : migration recente'' END AS verdict'
        WHEN 11 THEN 'FROM "' || t.owner || '"."DATABASECHANGELOGLOCK";'
        ELSE ' '
    END                                      AS ligne_generee
FROM (SELECT owner
        FROM all_tables
       WHERE table_name = 'DATABASECHANGELOGLOCK') t
CROSS JOIN (SELECT ROWNUM AS ordre_ligne
              FROM dual
           CONNECT BY ROWNUM <= 12) g
ORDER BY t.owner, g.ordre_ligne;

SET HEADING ON

CLEAR COLUMNS
PROMPT
PROMPT =========================================================================
PROMPT  Fin. Aucune modification n a ete faite sur cette base.
PROMPT =========================================================================
PROMPT
