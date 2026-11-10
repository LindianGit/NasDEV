create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_CONNECTION(
	RE_RELATIONSHIP_ID,
	RE_CONSTITUENT_ID,
	RE_RELATION_CONSTITUENT_ID,
	RECORD1_TYPE,
	RECORD1_D365_ID,
	RECORD2_TYPE,
	RECORD2_D365_ID,
	ROLE1_NAME,
	ROLE1_D365_ID,
	ROLE2_NAME,
	ROLE2_D365_ID,
	EFFECTIVE_START,
	EFFECTIVE_END,
	LOAD_ACTION,
	HOLD_REASON,
	PAYLOAD
) as
-- One row per pair of RE constituents that have a relationship. RE stores most
-- links twice (A to B and B to A), so one row is kept per pair: the row with
-- the most role names filled, then the earliest start, then the lowest RE id.
-- Two different relationship types between the same pair (for example employer
-- and friend) therefore collapse to one row. This is the "one-row-per-pair
-- rule" in gate CONNECTION_DIRECTION and is still to be agreed.
-- Rows with no second constituent are job details, not links, and are left out.
-- Record1 and Record2 follow the workbook: Record1 is CONSTITUENT_ID with the
-- relation description as its role, Record2 is RELATION_CONSTITUENT_ID with the
-- reciprocal description as its role. The direction is untested in DEV.
-- Dates in RE can be a year (2003) or a year and month (200006); these become
-- the first day of that period. Anything else becomes NULL.
-- A row is HOLD when a gate is open, when either end has no D365 id, is a
-- canvasser or is GDPR suppressed, or when a role is missing in D365.
WITH PAIRS AS (
    SELECT
        R.ID,
        R.CONSTITUENT_ID,
        R.RELATION_CONSTITUENT_ID,
        NULLIF(TRIM(R.RELATION_DESCRIPTION), '') AS ROLE1_NAME,
        NULLIF(TRIM(R.RECIP_RELATION_DESCRIPTION), '') AS ROLE2_NAME,
        CASE LENGTH(TRIM(R.DATE_FROM))
            WHEN 8 THEN TRY_TO_DATE(TRIM(R.DATE_FROM), 'YYYYMMDD')
            WHEN 6 THEN TRY_TO_DATE(TRIM(R.DATE_FROM) || '01', 'YYYYMMDD')
            WHEN 4 THEN TRY_TO_DATE(TRIM(R.DATE_FROM) || '0101', 'YYYYMMDD')
        END AS EFFECTIVE_START,
        CASE LENGTH(TRIM(R.DATE_TO))
            WHEN 8 THEN TRY_TO_DATE(TRIM(R.DATE_TO), 'YYYYMMDD')
            WHEN 6 THEN TRY_TO_DATE(TRIM(R.DATE_TO) || '01', 'YYYYMMDD')
            WHEN 4 THEN TRY_TO_DATE(TRIM(R.DATE_TO) || '0101', 'YYYYMMDD')
        END AS EFFECTIVE_END
    FROM RAW.RAISERS_EDGE.VW_ODS_T_RELATIONSHIPS AS R
    WHERE
        R.CONSTITUENT_ID IS NOT NULL
        AND R.RELATION_CONSTITUENT_ID IS NOT NULL
        AND R.CONSTITUENT_ID <> R.RELATION_CONSTITUENT_ID
),

ONE_PER_PAIR AS (
    SELECT *
    FROM PAIRS
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                LEAST(CONSTITUENT_ID, RELATION_CONSTITUENT_ID),
                GREATEST(CONSTITUENT_ID, RELATION_CONSTITUENT_ID)
            ORDER BY
                IFF(ROLE1_NAME IS NOT NULL, 1, 0)
                + IFF(ROLE2_NAME IS NOT NULL, 1, 0) DESC,
                EFFECTIVE_START ASC NULLS LAST,
                ID ASC
        ) = 1
),

-- Every RE constituent id mapped to its golden record, not only the oldest one,
-- because merged duplicates still appear in RE relationships
PARTY AS (
    SELECT
        X.SOURCE_RECORD_ID AS RE_CONSTITUENT_ID,
        IDS.D365_CONTACT_ID,
        IDS.D365_ACCOUNT_ID,
        IDS.IS_GDPR_SUPPRESSED
    FROM MDM_DB.GOLD.XREF AS X
    INNER JOIN MDM_DB.GOLD.VW_GOLDEN_RECORD_IDS AS IDS
        ON X.GOLDEN_RECORD_ID = IDS.GOLDEN_RECORD_ID
    WHERE X.SOURCE_SYSTEM = 'RAISERS_EDGE'
),

CANVASSER AS (
    SELECT
        CONSTITUENT_ID,
        COALESCE(ISCANVASSER, FALSE) AS IS_CANVASSER
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT
),

D365_ROLES AS (
    SELECT
        UPPER(TRIM(NAME)) AS NAME_KEY,
        CONNECTIONROLEID
    FROM RAW.DYNAMICS.VW_ODS_CONNECTIONROLES
    WHERE NULLIF(TRIM(NAME), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(NAME))
            ORDER BY CREATEDON, CONNECTIONROLEID
        ) = 1
),

-- Open gates that cover the whole table
GATES AS (
    SELECT
        -- LISTAGG gives an empty string, not NULL, when no gate is open
        NULLIF(
            LISTAGG(GATE_CODE, ',') WITHIN GROUP (ORDER BY GATE_CODE), ''
        ) AS GATE_CODES
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_REF_LOAD_GATE
    WHERE
        D365_TABLE = 'connection'
        AND IS_OPEN
        AND ROW_CONDITION_KEY IS NULL
),

RESOLVED AS (
    SELECT
        P.ID AS RE_RELATIONSHIP_ID,
        P.CONSTITUENT_ID AS RE_CONSTITUENT_ID,
        P.RELATION_CONSTITUENT_ID AS RE_RELATION_CONSTITUENT_ID,
        P.ROLE1_NAME,
        P.ROLE2_NAME,
        P.EFFECTIVE_START,
        P.EFFECTIVE_END,
        COALESCE(P1.D365_CONTACT_ID, P1.D365_ACCOUNT_ID) AS RECORD1_D365_ID,
        IFF(P1.D365_CONTACT_ID IS NOT NULL, 'contact', IFF(P1.D365_ACCOUNT_ID IS NOT NULL, 'account', NULL)) AS RECORD1_TYPE,
        COALESCE(P2.D365_CONTACT_ID, P2.D365_ACCOUNT_ID) AS RECORD2_D365_ID,
        IFF(P2.D365_CONTACT_ID IS NOT NULL, 'contact', IFF(P2.D365_ACCOUNT_ID IS NOT NULL, 'account', NULL)) AS RECORD2_TYPE,
        R1.CONNECTIONROLEID AS ROLE1_D365_ID,
        R2.CONNECTIONROLEID AS ROLE2_D365_ID,
        COALESCE(P1.IS_GDPR_SUPPRESSED, FALSE)
        OR COALESCE(P2.IS_GDPR_SUPPRESSED, FALSE) AS IS_SUPPRESSED,
        COALESCE(C1.IS_CANVASSER, FALSE)
        OR COALESCE(C2.IS_CANVASSER, FALSE) AS IS_CANVASSER,
        G.GATE_CODES
    FROM ONE_PER_PAIR AS P
    LEFT JOIN PARTY AS P1
        ON TO_VARCHAR(P.CONSTITUENT_ID) = P1.RE_CONSTITUENT_ID
    LEFT JOIN PARTY AS P2
        ON TO_VARCHAR(P.RELATION_CONSTITUENT_ID) = P2.RE_CONSTITUENT_ID
    LEFT JOIN CANVASSER AS C1
        ON P.CONSTITUENT_ID = C1.CONSTITUENT_ID
    LEFT JOIN CANVASSER AS C2
        ON P.RELATION_CONSTITUENT_ID = C2.CONSTITUENT_ID
    LEFT JOIN D365_ROLES AS R1
        ON UPPER(P.ROLE1_NAME) = R1.NAME_KEY
    LEFT JOIN D365_ROLES AS R2
        ON UPPER(P.ROLE2_NAME) = R2.NAME_KEY
    CROSS JOIN GATES AS G
),

REASONED AS (
    SELECT
        *,
        NULLIF(
            ARRAY_TO_STRING(
                ARRAY_CONSTRUCT_COMPACT(
                    IFF(GATE_CODES IS NOT NULL, 'GATE:' || GATE_CODES, NULL),
                    IFF(IS_SUPPRESSED, 'GDPR_SUPPRESSED', NULL),
                    IFF(IS_CANVASSER, 'CANVASSER', NULL),
                    IFF(RECORD1_D365_ID IS NULL, 'NO_D365_ID_RECORD1', NULL),
                    IFF(RECORD2_D365_ID IS NULL, 'NO_D365_ID_RECORD2', NULL),
                    IFF(ROLE1_NAME IS NULL, 'NO_ROLE1', IFF(ROLE1_D365_ID IS NULL, 'ROLE1_NOT_IN_D365', NULL)),
                    IFF(ROLE2_NAME IS NULL, 'NO_ROLE2', IFF(ROLE2_D365_ID IS NULL, 'ROLE2_NOT_IN_D365', NULL))
                ),
                ','
            ),
            ''
        ) AS HOLD_REASON
    FROM RESOLVED
)

SELECT
    RE_RELATIONSHIP_ID,
    RE_CONSTITUENT_ID,
    RE_RELATION_CONSTITUENT_ID,
    RECORD1_TYPE,
    RECORD1_D365_ID,
    RECORD2_TYPE,
    RECORD2_D365_ID,
    ROLE1_NAME,
    ROLE1_D365_ID,
    ROLE2_NAME,
    ROLE2_D365_ID,
    EFFECTIVE_START,
    EFFECTIVE_END,
    IFF(HOLD_REASON IS NULL, 'CREATE', 'HOLD') AS LOAD_ACTION,
    HOLD_REASON,
    OBJECT_CONSTRUCT(
        'record1objecttypecode', RECORD1_TYPE,
        'record1id', RECORD1_D365_ID,
        'record1roleid', ROLE1_D365_ID,
        'record2objecttypecode', RECORD2_TYPE,
        'record2id', RECORD2_D365_ID,
        'record2roleid', ROLE2_D365_ID,
        'effectivestart', TO_VARCHAR(EFFECTIVE_START, 'YYYY-MM-DD'),
        'effectiveend', TO_VARCHAR(EFFECTIVE_END, 'YYYY-MM-DD'),
        'statecode', IFF(EFFECTIVE_END IS NULL, 0, 1)
    ) AS PAYLOAD
FROM REASONED;