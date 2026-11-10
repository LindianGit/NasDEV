create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_MHA_CONSENTTYPE(
	RE_CONSENT_TYPE,
	D365_ID,
	LOAD_ACTION,
	HOLD_REASON,
	PAYLOAD,
	MHA_NAME
) as
-- One D365 consent type per distinct consent type name in the consent rule
-- map, ignoring case and padding. The map already strips a leading No, drops
-- the marker values (Seed, Assumed and similar) and adds the general
-- Marketing All Channels and FPS All Channels types. A type already in D365
-- (matched by name, ignoring case) is EXISTS and keeps its D365 id. Where D365
-- holds two rows of one name, the oldest wins.
-- The client loads consent types, so this view never offers a missing type for
-- creation: it is HOLD with HOLD_REASON CLIENT_LOADS until the type exists in
-- D365, and then EXISTS. Consent types are reference data, so GDPR does not
-- apply.
WITH RE_TYPES AS (
    SELECT TRIM(CONSENT_TYPE) AS RE_CONSENT_TYPE
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_REF_CONSENT_RULE
    WHERE NULLIF(TRIM(CONSENT_TYPE), '') IS NOT NULL
    GROUP BY TRIM(CONSENT_TYPE)
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(CONSENT_TYPE))
            ORDER BY COUNT(*) DESC, TRIM(CONSENT_TYPE)
        ) = 1
),

D365_TYPES AS (
    SELECT
        UPPER(TRIM(MHA_NAME)) AS NAME_KEY,
        MHA_CONSENTTYPEID
    FROM RAW.DYNAMICS.VW_ODS_MHA_CONSENTTYPES
    WHERE NULLIF(TRIM(MHA_NAME), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(MHA_NAME))
            ORDER BY CREATEDON, MHA_CONSENTTYPEID
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
        D365_TABLE = 'mha_consenttype'
        AND IS_OPEN
        AND ROW_CONDITION_KEY IS NULL
),

RESOLVED AS (
    SELECT
        R.RE_CONSENT_TYPE,
        T.MHA_CONSENTTYPEID AS D365_ID,
        G.GATE_CODES,
        R.RE_CONSENT_TYPE AS MHA_NAME
    FROM RE_TYPES AS R
    LEFT JOIN D365_TYPES AS T
        ON UPPER(TRIM(R.RE_CONSENT_TYPE)) = T.NAME_KEY
    CROSS JOIN GATES AS G
)

SELECT
    RE_CONSENT_TYPE,
    D365_ID,
    CASE
        WHEN D365_ID IS NOT NULL THEN 'EXISTS'
        ELSE 'HOLD'
    END AS LOAD_ACTION,
    CASE
        WHEN D365_ID IS NOT NULL THEN NULL
        WHEN GATE_CODES IS NOT NULL THEN 'GATE:' || GATE_CODES
        ELSE 'CLIENT_LOADS'
    END AS HOLD_REASON,
    OBJECT_CONSTRUCT('mha_name', MHA_NAME) AS PAYLOAD,
    MHA_NAME
FROM RESOLVED;