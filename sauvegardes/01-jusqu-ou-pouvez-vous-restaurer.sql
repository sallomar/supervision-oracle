-- ===========================================================================
-- SCRIPT        : 01-jusqu-ou-pouvez-vous-restaurer.sql
-- OBJECTIF      : Vous sauvegardez. Jusqu ou pouvez-vous restaurer ? Le mode de
--                 journalisation, la derniere sauvegarde reussie, la chaine des
--                 journaux archives, et l ecart en heures jusqu au dernier point
--                 restaurable lisible d ici.
-- CE QUE CE     : une garantie. Ce script ne dit jamais qu une base est
-- N EST PAS       sauvegardee, ni qu une restauration reussira. Seul un test de
--                 restauration le prouve. Il dit ce qui est lisible, et ce qui
--                 ne l est pas d ou vous etes connecte.
-- VUES          : V$DATABASE (section 1), V$RMAN_BACKUP_JOB_DETAILS et
--                 V$BACKUP_PIECE (section 2), V$ARCHIVED_LOG (section 3),
--                 V$RMAN_CONFIGURATION et V$RECOVERY_FILE_DEST (section 4)
-- PRIVILEGES    : SELECT sur V_$DATABASE, V_$RMAN_BACKUP_JOB_DETAILS,
--                 V_$BACKUP_PIECE, V_$ARCHIVED_LOG, V_$RMAN_CONFIGURATION et
--                 V_$RECOVERY_FILE_DEST (ou SELECT_CATALOG_ROLE). Aucune vue
--                 sous licence. V$BACKUP et V$DATAFILE_HEADER, souvent refusees
--                 a un compte de lecture, ne sont pas utilisees.
-- LECTURE SEULE : que des SELECT. Aucun DDL, aucun DML, aucun ALTER, aucun RMAN.
-- ECRIT POUR    : Oracle 11.2 et superieur. Sur 11g, la ligne CONTENEUR rend
--                 ORA-02003 (pas de conteneurs) : c est attendu, ignore-la.
-- EXECUTE SUR   : Oracle 21c Express Edition 21.0.0.0.0, base multitenant en
--                 ARCHIVELOG avec une sauvegarde RMAN, depuis CDB$ROOT et
--                 depuis une PDB, en SYSDBA puis avec un compte de lecture non
--                 privilegie. Pas encore execute sur 11.2 ni sur 19c.
-- CDB           : lance-le depuis CDB$ROOT. Dans V$RMAN_BACKUP_JOB_DETAILS,
--                 CON_ID vaut 0, 1 ou l identifiant du conteneur concerne
--                 (reference 19c, 8.172). Mesure sur 21c XE : une sauvegarde
--                 pilotee depuis la racine porte CON_ID 1, et la vue ne rend
--                 donc AUCUNE ligne depuis une PDB, meme deux minutes apres.
--                 Une sauvegarde lancee en se connectant directement a la PDB
--                 n a pas ete testee. Le script detecte le cas et le dit
--                 (section 2) au lieu de conclure « aucune sauvegarde ». C est
--                 l inverse du script des licences, qui se lance DANS chaque PDB.
-- PERIMETRE     : bases SINGLE-INSTANCE. Sauvegardes RMAN sur disque ou bande ;
--                 les copies faites hors RMAN ne sont pas visibles ici.
-- A SAVOIR      : les vues V$ lisent le FICHIER DE CONTROLE. Un journal archive
--                 deja efface (DELETED = YES) y garde une ligne : le script
--                 filtre sur ceux qui restent sur disque, et les compte par
--                 journal et non par destination d archivage. REUSSIE veut dire
--                 STATUS = COMPLETED strict : COMPLETED WITH ERRORS et
--                 COMPLETED WITH WARNINGS sont listes a part. Les seuils d age
--                 affiches (48 h, 192 h, 336 h) sont ceux d une supervision par
--                 environnement, production / test / developpement ; ce sont
--                 des reperes de repli, votre cadence de sauvegarde fait foi.
-- USAGE         : SQL> @01-jusqu-ou-pouvez-vous-restaurer.sql
--
-- Limites connues (conteneurs, fichier de controle, bande) : README du dossier.
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
PROMPT  JUSQU OU POUVEZ-VOUS RESTAURER  ==  lecture seule, pas une garantie
PROMPT =========================================================================
PROMPT
PROMPT === SECTION 1 : mode de journalisation et conteneur =====================
PROMPT  Le mode decide de tout. Une sauvegarde pilotee depuis la racine n
PROMPT  apparait pas dans la vue des travaux lue d une PDB : lance-le d en haut.
PROMPT

COLUMN nom_base      FORMAT A10   HEADING "BASE"
COLUMN mode_journal  FORMAT A14   HEADING "JOURNALISATION"
COLUMN ouverture     FORMAT A11   HEADING "OUVERTURE"
COLUMN lecture_mode  FORMAT A62   HEADING "LECTURE"

SELECT
    name       AS nom_base,
    log_mode   AS mode_journal,
    open_mode  AS ouverture,
    CASE log_mode
        WHEN 'ARCHIVELOG' THEN 'ARCHIVELOG : restauration possible jusqu au dernier journal'
        ELSE                   'NOARCHIVELOG : restauration au point de la derniere sauvegarde'
    END        AS lecture_mode
FROM v$database;

COLUMN conteneur FORMAT A30 HEADING "CONTENEUR COURANT"
PROMPT  (sur Oracle 11g la ligne suivante rend ORA-02003 : pas de conteneurs, attendu)
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS conteneur FROM dual;

PROMPT
PROMPT === SECTION 2 : la derniere sauvegarde reussie, par type ================
PROMPT  REUSSIE = STATUS COMPLETED strict. COMPLETED WITH ERRORS et COMPLETED
PROMPT  WITH WARNINGS sont des echecs partiels : ils sont listes juste apres.
PROMPT  Les seuils d age sont des reperes par environnement, pas un verdict.
PROMPT

COLUMN type_sauvegarde FORMAT A16        HEADING "TYPE"
COLUMN derniere_fin    FORMAT A16        HEADING "DERNIERE REUSSIE"
COLUMN duree_s         FORMAT 9999999    HEADING "DUREE|(SEC)"
COLUMN volume_mo       FORMAT 99999999   HEADING "VOLUME|(MO)"
COLUMN age_h           FORMAT 9999990.0  HEADING "AGE|(HEURES)"
COLUMN lecture_age     FORMAT A34        HEADING "LECTURE (REPERES 48 / 192 / 336 H)"

-- Un travail = une execution RMAN. STATUS vaut aussi COMPLETED WITH ERRORS et
-- COMPLETED WITH WARNINGS (reference 19c, 8.172) : les compter comme reussis
-- afficherait un echec partiel en vert. Filtre strict ici, liste a part ensuite.
SELECT
    type_sauvegarde,
    derniere_fin,
    duree_s,
    volume_mo,
    age_h,
    CASE
        WHEN age_h > 336 THEN 'AU-DELA DE TOUS LES REPERES (336 H)'
        WHEN age_h > 192 THEN 'AU-DELA DU REPERE TEST (192 H)'
        WHEN age_h > 48  THEN 'AU-DELA DU REPERE PROD (48 H)'
        ELSE                  'DANS LE REPERE PROD (48 H)'
    END AS lecture_age
FROM (
    SELECT
        j.input_type                                     AS type_sauvegarde,
        TO_CHAR(MAX(j.end_time), 'DD/MM/YYYY HH24:MI')   AS derniere_fin,
        MAX(j.elapsed_seconds) KEEP (DENSE_RANK LAST ORDER BY j.end_time)        AS duree_s,
        ROUND(MAX(j.output_bytes) KEEP (DENSE_RANK LAST ORDER BY j.end_time) / 1024 / 1024) AS volume_mo,
        ROUND((SYSDATE - MAX(j.end_time)) * 24, 1)       AS age_h
    FROM v$rman_backup_job_details j
    WHERE j.status = 'COMPLETED'
    GROUP BY j.input_type
)
ORDER BY age_h;

COLUMN statut_partiel  FORMAT A24      HEADING "STATUT NON REUSSI"
COLUMN type_partiel    FORMAT A16      HEADING "TYPE"
COLUMN dernier_partiel FORMAT A16      HEADING "DERNIER"
COLUMN nb_partiel      FORMAT 999999   HEADING "NOMBRE"
COLUMN lecture_partiel FORMAT A40      HEADING "LECTURE"

PROMPT
PROMPT  Et ce qui n a PAS entierement reussi. Aucune ligne ici est un resultat,
PROMPT  pas une absence : aucun travail en erreur, en avertissement ni en cours.
PROMPT

SELECT
    status                                            AS statut_partiel,
    input_type                                        AS type_partiel,
    TO_CHAR(MAX(end_time), 'DD/MM/YYYY HH24:MI')      AS dernier_partiel,
    COUNT(*)                                          AS nb_partiel,
    CASE
        WHEN status = 'COMPLETED WITH ERRORS'   THEN 'ECHEC PARTIEL : A TRAITER COMME UN ECHEC'
        WHEN status = 'COMPLETED WITH WARNINGS' THEN 'AVERTISSEMENTS : A LIRE DANS RMAN'
        WHEN status = 'FAILED'                  THEN 'ECHEC : AUCUNE SAUVEGARDE UTILISABLE ICI'
        WHEN status LIKE 'RUNNING%'             THEN 'EN COURS AU MOMENT DE LA LECTURE'
        ELSE                                         'A LIRE DANS LE JOURNAL RMAN'
    END                                               AS lecture_partiel
FROM   v$rman_backup_job_details
WHERE  status <> 'COMPLETED'
GROUP  BY status, input_type
ORDER  BY MAX(end_time) DESC;

COLUMN nb_pieces       FORMAT 9999999  HEADING "PIECES|DISPONIBLES"
COLUMN derniere_piece  FORMAT A16      HEADING "DERNIERE PIECE"
COLUMN lecture_pieces  FORMAT A54      HEADING "LECTURE"

-- Repli : si la vue des travaux ne rend AUCUNE ligne, les pieces du fichier de
-- controle disent s il existe quand meme une sauvegarde, pilotee d ailleurs.
SELECT
    nb_pieces,
    derniere_piece,
    CASE
        WHEN nb_travaux > 0 THEN 'DETAIL DES TRAVAUX CI-DESSUS'
        WHEN nb_pieces  > 0 THEN 'PILOTE DEPUIS LA RACINE, DETAIL NON VISIBLE D ICI'
        ELSE                     'AUCUNE PIECE DE SAUVEGARDE DANS LE FICHIER DE CONTROLE'
    END AS lecture_pieces
FROM (
    SELECT
        COUNT(*)                                                  AS nb_pieces,
        TO_CHAR(MAX(p.completion_time), 'DD/MM/YYYY HH24:MI')     AS derniere_piece
    FROM v$backup_piece p
    WHERE p.status = 'A'
) pieces,
(
    SELECT COUNT(*) AS nb_travaux
    FROM v$rman_backup_job_details
) travaux;

PROMPT
PROMPT === SECTION 3 : la chaine des journaux, et l ecart jusqu au point restaurable
PROMPT  Une sauvegarde ouverte n est restaurable qu avec les journaux archives
PROMPT  pendant et apres elle : le point restaurable est le dernier journal
PROMPT  SAUVEGARDE. Ceux encore sur disque sans sauvegarde sont le retard.
PROMPT

COLUMN journaux_disque    FORMAT 9999999  HEADING "JOURNAUX|SUR DISQUE"
COLUMN non_sauvegardes    FORMAT 9999999  HEADING "DONT NON|SAUVEGARDES"
COLUMN plus_ancien_non_sv FORMAT A16      HEADING "PLUS ANCIEN|NON SAUVEGARDE"
COLUMN point_restaurable  FORMAT A16      HEADING "DERNIER POINT|RESTAURABLE"
COLUMN ecart_h            FORMAT 9999990.0 HEADING "ECART|(HEURES)"
COLUMN lecture_chaine     FORMAT A46      HEADING "LECTURE"

-- Point restaurable : en ARCHIVELOG, le dernier journal archive SAUVEGARDE (une
-- sauvegarde ouverte exige les journaux pris pendant et apres elle) ; en
-- NOARCHIVELOG, la derniere piece de sauvegarde, et rien apres.
-- V$ARCHIVED_LOG porte une ligne par DESTINATION d archivage : on compte les
-- journaux distincts, sinon une base qui multiplexe ses archives compte double.
SELECT
    journaux_disque,
    non_sauvegardes,
    plus_ancien_non_sv,
    TO_CHAR(point_restaurable, 'DD/MM/YYYY HH24:MI')  AS point_restaurable,
    ROUND((SYSDATE - point_restaurable) * 24, 1)      AS ecart_h,
    CASE
        WHEN mode_journal <> 'ARCHIVELOG' THEN 'NOARCHIVELOG : PAS DE CHAINE, POINT = SAUVEGARDE'
        WHEN point_restaurable IS NULL    THEN 'AUCUN JOURNAL SAUVEGARDE : POINT NON ETABLI'
        WHEN non_sauvegardes > 0          THEN 'JOURNAUX NON SAUVEGARDES : LE POINT EST EN RETARD'
        ELSE                                   'CHAINE SAUVEGARDEE JUSQU AU DERNIER JOURNAL'
    END AS lecture_chaine
FROM (
    SELECT
        mode_journal,
        journaux_disque,
        non_sauvegardes,
        plus_ancien_non_sv,
        CASE
            WHEN mode_journal = 'ARCHIVELOG' THEN dernier_journal_sv_dt
            ELSE                                  derniere_piece_dt
        END AS point_restaurable
    FROM (
        SELECT
            (SELECT log_mode FROM v$database)                                    AS mode_journal,
            (SELECT COUNT(DISTINCT thread# || '-' || sequence#) FROM v$archived_log
             WHERE deleted = 'NO')                                               AS journaux_disque,
            (SELECT COUNT(DISTINCT thread# || '-' || sequence#) FROM v$archived_log
             WHERE deleted = 'NO' AND backup_count = 0)                          AS non_sauvegardes,
            (SELECT TO_CHAR(MIN(completion_time), 'DD/MM/YYYY HH24:MI')
             FROM v$archived_log
             WHERE deleted = 'NO' AND backup_count = 0)                          AS plus_ancien_non_sv,
            (SELECT MAX(completion_time) FROM v$backup_piece WHERE status = 'A') AS derniere_piece_dt,
            (SELECT MAX(next_time) FROM v$archived_log WHERE backup_count > 0)   AS dernier_journal_sv_dt
        FROM dual
    )
);

PROMPT
PROMPT === SECTION 4 : ce qui est configure, et qui ne prouve rien =============
PROMPT  Une politique declaree n est pas une politique appliquee. Section RMAN
PROMPT  vide : aucune configuration explicite, valeurs par defaut d Oracle.
PROMPT

COLUMN parametre_rman FORMAT A30 HEADING "CONFIGURATION RMAN"
COLUMN valeur_rman    FORMAT A60 HEADING "VALEUR"

SELECT name AS parametre_rman, value AS valeur_rman
FROM   v$rman_configuration
ORDER  BY conf#;

COLUMN zone_recup    FORMAT A44        HEADING "ZONE DE RECUPERATION"
COLUMN limite_go     FORMAT 999990.0   HEADING "LIMITE|(GO)"
COLUMN utilise_go    FORMAT 999990.00  HEADING "UTILISE|(GO)"
COLUMN recup_go      FORMAT 999990.00  HEADING "RECUPERABLE|(GO)"
COLUMN effectif_pct  FORMAT 990.0      HEADING "USAGE|EFFECTIF %"
COLUMN lecture_zone  FORMAT A36        HEADING "LECTURE (CRITIQUE A 90 % EFFECTIF)"

-- Usage effectif = (utilise - recuperable) / limite : ce qu Oracle ne pourra pas
-- liberer seul. Une zone pleine arrete les sauvegardes et l archivage.
-- Epine sur DUAL : sans zone configuree la vue ne rend aucune ligne, et une
-- section vide ne dirait pas pourquoi.
SELECT
    NVL(r.name, '(aucune zone configuree)')                     AS zone_recup,
    ROUND(r.space_limit / 1024 / 1024 / 1024, 1)                AS limite_go,
    ROUND(r.space_used / 1024 / 1024 / 1024, 2)                 AS utilise_go,
    ROUND(r.space_reclaimable / 1024 / 1024 / 1024, 2)          AS recup_go,
    CASE WHEN NVL(r.space_limit, 0) > 0
         THEN ROUND(100 * (r.space_used - r.space_reclaimable) / r.space_limit, 1) END AS effectif_pct,
    CASE
        WHEN NVL(r.space_limit, 0) = 0 THEN 'AUCUNE ZONE : RIEN A SURVEILLER ICI'
        WHEN 100 * (r.space_used - r.space_reclaimable) / r.space_limit >= 90
             THEN 'CRITIQUE : >= 90 % NON RECUPERABLE'
        ELSE 'OK'
    END                                                         AS lecture_zone
FROM dual d
LEFT JOIN v$recovery_file_dest r ON 1 = 1;

PROMPT
PROMPT =========================================================================
PROMPT  Fin. Aucune modification n a ete faite sur cette base.
PROMPT  Seul un test de restauration prouve qu une sauvegarde est restaurable.
PROMPT =========================================================================
PROMPT

CLEAR COLUMNS
