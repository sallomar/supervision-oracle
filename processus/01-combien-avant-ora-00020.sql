-- ===========================================================================
-- SCRIPT        : 01-combien-avant-ora-00020.sql
-- OBJECTIF      : A quelle distance de ORA-00020 (processus) et de ORA-00018
--                 (sessions) l instance est-elle passee depuis son demarrage,
--                 et qui occupe les connexions en ce moment.
-- VUES          : V$INSTANCE, V$RESOURCE_LIMIT et V$PARAMETER (section 1),
--                 V$SESSION (section 2)
-- PRIVILEGES    : SELECT sur V_$INSTANCE, V_$RESOURCE_LIMIT, V_$PARAMETER et
--                 V_$SESSION (ou SELECT_CATALOG_ROLE). Aucune vue sous licence.
-- LECTURE SEULE : que des SELECT. Aucun DDL, aucun DML, aucun ALTER.
-- ECRIT POUR    : Oracle 11.2 et superieur (aucune syntaxe recente : ni
--                 FETCH FIRST, ni CON_ID, ni SYS_CONTEXT sur le conteneur).
-- EXECUTE SUR   : Oracle 21c Express Edition 21.0.0.0.0, base multitenant,
--                 depuis une PDB et depuis CDB$ROOT, en SYSDBA puis avec un
--                 compte de lecture non privilegie. Pas encore execute sur
--                 11.2 ni sur 19c.
-- CDB           : lance-le depuis CDB$ROOT. La limite est celle de l INSTANCE,
--                 toutes PDB comprises, mais V$RESOURCE_LIMIT est VIDE depuis
--                 une PDB : la section 1 y montre la limite et signale que
--                 l occupation et le pic ne sont pas visibles de la. Depuis
--                 une PDB, la section 2 ne voit que les sessions de la PDB.
-- PERIMETRE     : bases SINGLE-INSTANCE. En RAC, ces vues sont locales au
--                 noeud : chaque noeud a sa propre limite et son propre pic.
-- A SAVOIR      : MAX_UTILIZATION repart a zero a chaque demarrage de
--                 l instance. Un pic bas juste apres un STARTUP ne dit rien.
-- USAGE         : SQL> @01-combien-avant-ora-00020.sql
--
-- Limites connues (CDB/PDB, RAC, processus d arriere-plan) : README du dossier.
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
PROMPT  COMBIEN AVANT ORA-00020  ==  lecture seule, aucune modification
PROMPT =========================================================================
PROMPT
PROMPT === SECTION 1 : distance a la limite, en cours et pic depuis le demarrage
PROMPT

COLUMN instance_nom   FORMAT A16      HEADING "INSTANCE"
COLUMN demarree_le    FORMAT A19      HEADING "DEMARREE LE"
COLUMN depuis_jours   FORMAT 99990.0  HEADING "DEPUIS|(JOURS)"

SELECT
    i.instance_name                                  AS instance_nom,
    TO_CHAR(i.startup_time, 'DD/MM/YYYY HH24:MI:SS') AS demarree_le,
    ROUND(SYSDATE - i.startup_time, 1)               AS depuis_jours
FROM v$instance i;

COLUMN ressource       FORMAT A10          HEADING "RESSOURCE"
COLUMN erreur_si_plein FORMAT A9           HEADING "ERREUR|SI PLEIN"
COLUMN en_cours        FORMAT 9999999      HEADING "EN|COURS"
COLUMN pic             FORMAT 9999999999   HEADING "PIC DEPUIS|DEMARRAGE"
COLUMN limite          FORMAT 9999999      HEADING "LIMITE"
COLUMN pct_en_cours    FORMAT 9990.0       HEADING "% EN|COURS"
COLUMN pct_pic         FORMAT 9990.0       HEADING "% DU|PIC"
COLUMN verdict         FORMAT A27          HEADING "VERDICT|(SUR LE PIC)"

-- Le verdict porte sur le PIC, pas sur l instant : un script lance une fois
-- ne voit que le moment ou on le lance. Le pic est la memoire d Oracle.
-- Epine de deux lignes en LEFT JOIN : depuis une PDB, V$RESOURCE_LIMIT est
-- vide et la ligne s affiche quand meme, avec la limite et un verdict qui le dit.
SELECT
    ressource,
    erreur_si_plein,
    en_cours,
    pic,
    limite,
    ROUND(100 * en_cours / limite, 1)                AS pct_en_cours,
    ROUND(100 * pic / limite, 1)                     AS pct_pic,
    CASE
        WHEN pic IS NULL                    THEN 'NON VISIBLE : voir CDB$ROOT'
        WHEN limite IS NULL                 THEN 'LIMITE NON NUMERIQUE'
        WHEN 100 * pic / limite > 90        THEN 'CRITIQUE : pic > 90 %'
        WHEN 100 * pic / limite > 70        THEN 'ATTENTION : pic > 70 %'
        ELSE                                     'OK'
    END                                              AS verdict
FROM (
    SELECT
        x.ressource,
        x.erreur_si_plein,
        r.current_utilization                        AS en_cours,
        r.max_utilization                            AS pic,
        CASE
            WHEN REGEXP_LIKE(TRIM(r.limit_value), '^[0-9]+$')
                 THEN TO_NUMBER(TRIM(r.limit_value))
            ELSE (SELECT MAX(TO_NUMBER(p.value))
                  FROM v$parameter p
                  WHERE p.name = x.ressource)
        END                                          AS limite,
        x.ordre
    FROM (
        SELECT 'processes' AS ressource, 'ORA-00020' AS erreur_si_plein, 1 AS ordre FROM dual
        UNION ALL
        SELECT 'sessions'  AS ressource, 'ORA-00018' AS erreur_si_plein, 2 AS ordre FROM dual
    ) x
    LEFT JOIN v$resource_limit r
      ON r.resource_name = x.ressource
)
ORDER BY ordre;

PROMPT
PROMPT === SECTION 2 : qui occupe les connexions, par utilisateur et programme ==
PROMPT  Sessions utilisateur seulement : les processus d arriere-plan occupent
PROMPT  aussi des slots. Depuis une PDB, seules les sessions de la PDB sont vues.
PROMPT

COLUMN utilisateur      FORMAT A20             HEADING "UTILISATEUR"
COLUMN programme        FORMAT A30             HEADING "PROGRAMME"
COLUMN machine          FORMAT A25             HEADING "MACHINE"
COLUMN nb_sessions      FORMAT 99999999        HEADING "SESSIONS"
COLUMN nb_inactives     FORMAT 999999999       HEADING "DONT|INACTIVES"
COLUMN inactive_max_min FORMAT 9999999999999   HEADING "INACTIVE LA|PLUS ANCIENNE|(MINUTES)"

SELECT
    utilisateur,
    programme,
    machine,
    nb_sessions,
    nb_inactives,
    inactive_max_min
FROM (
    SELECT
        NVL(s.username, '(sans nom)')                 AS utilisateur,
        NVL(SUBSTR(s.program, 1, 30), '(inconnu)')    AS programme,
        NVL(SUBSTR(s.machine, 1, 25), '(inconnue)')   AS machine,
        COUNT(*)                                      AS nb_sessions,
        SUM(CASE WHEN s.status = 'INACTIVE' THEN 1 ELSE 0 END) AS nb_inactives,
        MAX(CASE WHEN s.status = 'INACTIVE'
                 THEN FLOOR(s.last_call_et / 60) END) AS inactive_max_min
    FROM v$session s
    WHERE s.type = 'USER'
    GROUP BY s.username, SUBSTR(s.program, 1, 30), SUBSTR(s.machine, 1, 25)
    ORDER BY COUNT(*) DESC, s.username
)
WHERE ROWNUM <= 10;

PROMPT
PROMPT =========================================================================
PROMPT  Fin. Aucune modification n a ete faite sur cette base.
PROMPT =========================================================================
PROMPT

CLEAR COLUMNS
