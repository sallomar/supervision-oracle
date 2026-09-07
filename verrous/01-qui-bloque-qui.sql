-- ===========================================================================
-- SCRIPT        : 01-qui-bloque-qui.sql
-- OBJECTIF      : Qui bloque qui, depuis combien de temps, et quelle session
--                 traiter. Le verdict porte sur l attente SUBIE par le bloque.
-- VUES          : V$SESSION (sections 1 a 3), DBA_OBJECTS (section 3)
-- PRIVILEGES    : SELECT sur V_$SESSION (ou SELECT_CATALOG_ROLE)
--                 SELECT sur DBA_OBJECTS pour la section 3
-- LECTURE SEULE : que des SELECT. Aucun DDL, aucun DML, aucun ALTER.
-- ECRIT POUR    : Oracle 11.2 et superieur (colonnes V$SESSION de longue date,
--                 aucune fonction dependante d une version recente).
-- EXECUTE SUR   : Oracle 21c Express Edition 21.0.0.0.0, base multitenant, a la
--                 fois depuis CDB$ROOT et depuis une PDB, en SYSDBA puis avec un
--                 compte de lecture non privilegie. Pas encore execute sur 11.2
--                 ni sur 19c.
-- CDB           : lance-le DANS la PDB. Depuis CDB$ROOT la section 3 ne peut pas
--                 nommer un objet de PDB, et affiche alors son OBJECT_ID.
-- PERIMETRE     : bases SINGLE-INSTANCE. En RAC, une chaine dont le bloqueur est
--                 sur un autre noeud reste AFFICHEE et signalee hors perimetre.
--                 Elle n est jamais resolue vers la session locale portant le
--                 meme SID, qui n a aucun rapport avec elle.
-- A SAVOIR      : SECONDS_IN_WAIT est depreciee en 19c au profit de
--                 WAIT_TIME_MICRO. Conservee ici pour la compatibilite
--                 descendante et l alignement sur le runbook du produit.
-- USAGE         : SQL> @01-qui-bloque-qui.sql
--
-- Limites connues (RAC, CDB/PDB, largeur d affichage) : README du dossier.
-- ===========================================================================

SET DEFINE OFF
SET LINESIZE 240
SET PAGESIZE 100
SET FEEDBACK ON
SET TRIMSPOOL ON
CLEAR COLUMNS

PROMPT
PROMPT =========================================================================
PROMPT  QUI BLOQUE QUI  ==  lecture seule, aucune modification de la base
PROMPT =========================================================================
PROMPT
PROMPT === SECTION 1 : chaines de blocage en cours =============================
PROMPT

-- SERIAL#, programme, machine et utilisateur OS du bloqueur sont en section 2 :
-- ici on situe, la-bas on agit. Garder tout sur une ligne la rendait illisible.
COLUMN bloqueur_sid       FORMAT 99999        HEADING "BLOQUEUR|SID"
COLUMN bloqueur_user      FORMAT A18          HEADING "BLOQUEUR|UTILISATEUR"
COLUMN bloqueur_statut    FORMAT A9           HEADING "BLOQUEUR|STATUT"
COLUMN bloqueur_depuis    FORMAT A30          HEADING "BLOQUEUR|DEPUIS"
COLUMN bloque_sid         FORMAT 99999        HEADING "BLOQUE|SID"
COLUMN bloque_user        FORMAT A18          HEADING "BLOQUE|UTILISATEUR"
COLUMN bloque_attente     FORMAT A30          HEADING "BLOQUE|EVENEMENT D ATTENTE"
COLUMN attente_min        FORMAT 99990.9      HEADING "ATTENTE|MINUTES"
COLUMN verdict            FORMAT A15          HEADING "VERDICT|(ATTENTE SUBIE)"

-- Le SID affiche est celui rendu par BLOCKING_SESSION, meme distant. La jointure,
-- elle, est bornee a l instance courante : sans cela un SID distant designerait
-- une session locale sans aucun rapport (voir PERIMETRE en en-tete).
SELECT
    w.blocking_session                           AS bloqueur_sid,
    CASE WHEN b.sid IS NULL
         THEN '(instance ' || TO_CHAR(w.blocking_instance) || ')'
         ELSE NVL(b.username, '(processus interne)')
    END                                          AS bloqueur_user,
    NVL(b.status, 'DISTANT')                     AS bloqueur_statut,
    -- LAST_CALL_ET se lit dans deux sens selon le statut de la session.
    CASE
        WHEN b.sid IS NULL         THEN 'hors perimetre single-instance'
        WHEN b.status = 'ACTIVE'   THEN 'appel en cours depuis '
                             || TO_CHAR(FLOOR(b.last_call_et / 60)) || ' min'
        WHEN b.status = 'INACTIVE' THEN 'aucun appel depuis '
                             || TO_CHAR(FLOOR(b.last_call_et / 60)) || ' min'
        ELSE                       'statut ' || b.status || ' depuis '
                             || TO_CHAR(FLOOR(b.last_call_et / 60)) || ' min'
    END                                          AS bloqueur_depuis,
    w.sid                                        AS bloque_sid,
    NVL(w.username, '(processus interne)')       AS bloque_user,
    w.event                                      AS bloque_attente,
    ROUND(w.seconds_in_wait / 60, 1)             AS attente_min,
    CASE
        WHEN w.seconds_in_wait / 60 > 30 THEN 'CRITIQUE'
        WHEN w.seconds_in_wait / 60 > 10 THEN 'ATTENTION'
        ELSE                                  'INFO'
    END                                          AS verdict
FROM v$session w
LEFT JOIN v$session b
  ON  b.sid = w.blocking_session
  AND w.blocking_instance = (SELECT instance_number FROM v$instance)
WHERE w.blocking_session IS NOT NULL
  AND w.blocking_session_status = 'VALID'
ORDER BY w.seconds_in_wait DESC;

PROMPT
PROMPT === SECTION 2 : tete(s) de chaine ======================================
PROMPT  Celle qui bloque sans etre bloquee : la seule sur laquelle agir.
PROMPT

COLUMN tete_sid          FORMAT 99999      HEADING "TETE|SID"
COLUMN tete_serial       FORMAT 9999999    HEADING "TETE|SERIAL#"
COLUMN tete_user         FORMAT A18        HEADING "TETE|UTILISATEUR"
COLUMN tete_statut       FORMAT A9         HEADING "TETE|STATUT"
COLUMN depuis_min        FORMAT 999990     HEADING "SANS APPEL|OU ACTIVE (MIN)"
COLUMN sessions_bloquees FORMAT 99990      HEADING "SESSIONS|BLOQUEES"
COLUMN tete_programme    FORMAT A22        HEADING "PROGRAMME"
COLUMN tete_machine      FORMAT A18        HEADING "MACHINE"
COLUMN tete_osuser       FORMAT A14        HEADING "UTILISATEUR OS"
COLUMN tete_sql_id       FORMAT A15        HEADING "DERNIER|SQL_ID"

SELECT
    t.sid                                    AS tete_sid,
    t.serial#                                AS tete_serial,
    NVL(t.username, '(processus interne)')   AS tete_user,
    t.status                                 AS tete_statut,
    FLOOR(t.last_call_et / 60)               AS depuis_min,
    (SELECT COUNT(*)
       FROM v$session x
      WHERE x.blocking_session = t.sid
        AND x.blocking_session_status = 'VALID'
        AND x.blocking_instance = (SELECT instance_number FROM v$instance)) AS sessions_bloquees,
    NVL(t.program, '(inconnu)')              AS tete_programme,
    NVL(t.machine, '(inconnue)')             AS tete_machine,
    NVL(t.osuser,  '(inconnu)')              AS tete_osuser,
    t.sql_id                                 AS tete_sql_id
FROM v$session t
WHERE t.sid IN (SELECT s.blocking_session
                  FROM v$session s
                 WHERE s.blocking_session IS NOT NULL
                   AND s.blocking_session_status = 'VALID'
                   AND s.blocking_instance = (SELECT instance_number FROM v$instance))
  AND t.blocking_session IS NULL
ORDER BY sessions_bloquees DESC;

PROMPT
PROMPT === SECTION 3 : objets sur lesquels portent les attentes ===============
PROMPT

COLUMN bloque_sid2   FORMAT 99999   HEADING "BLOQUE|SID"
COLUMN bloque_user2  FORMAT A18     HEADING "BLOQUE|UTILISATEUR"
COLUMN proprietaire  FORMAT A20     HEADING "PROPRIETAIRE"
COLUMN objet         FORMAT A30     HEADING "OBJET"
COLUMN type_objet    FORMAT A18     HEADING "TYPE"
COLUMN fichier       FORMAT 99999   HEADING "FICHIER"
COLUMN bloc          FORMAT 99999999 HEADING "BLOC"

-- LEFT JOIN volontaire : DBA_OBJECTS s arrete au conteneur courant. Une
-- jointure interne perdait la ligne en silence depuis CDB$ROOT.
SELECT
    w.sid                                    AS bloque_sid2,
    NVL(w.username, '(processus interne)')   AS bloque_user2,
    NVL(o.owner, '(non resolu)')             AS proprietaire,
    NVL(o.object_name,
        'OBJECT_ID ' || TO_CHAR(w.row_wait_obj#))  AS objet,
    NVL(o.object_type, '(autre conteneur)')  AS type_objet,
    w.row_wait_file#                         AS fichier,
    w.row_wait_block#                        AS bloc
FROM v$session w
LEFT JOIN dba_objects o
  ON o.object_id = w.row_wait_obj#
WHERE w.blocking_session IS NOT NULL
  AND w.blocking_session_status = 'VALID'
  AND w.row_wait_obj# <> -1
ORDER BY o.owner, o.object_name;

CLEAR COLUMNS
PROMPT
PROMPT =========================================================================
PROMPT  Fin. Aucune modification n a ete faite sur cette base.
PROMPT =========================================================================
PROMPT
