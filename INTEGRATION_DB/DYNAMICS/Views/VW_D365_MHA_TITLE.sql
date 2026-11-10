create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_MHA_TITLE(
	RE_TITLE,
	D365_ID,
	LOAD_ACTION,
	HOLD_REASON,
	PAYLOAD,
	MHA_NAME
) as
-- One D365 title per distinct RE title, ignoring case and padding. The most
-- frequent RE spelling is used. A title already in D365 (matched by name,
-- ignoring case) is EXISTS and keeps its D365 id. Where D365 holds two rows of
-- one name, the oldest wins. Titles are reference data, so GDPR does not apply.
WITH RE_TITLES AS (
    SELECT TITLE1 AS RE_TITLE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT
    WHERE TITLE1 IS NOT NULL
    GROUP BY TITLE1
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(TITLE1))
            ORDER BY COUNT(*) DESC, TITLE1
        ) = 1
),

D365_TITLES AS (
    SELECT
        UPPER(TRIM(MHA_NAME)) AS NAME_KEY,
        MHA_TITLEID
    FROM RAW.DYNAMICS.VW_ODS_MHA_TITLES
    WHERE NULLIF(TRIM(MHA_NAME), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(MHA_NAME))
            ORDER BY CREATEDON, MHA_TITLEID
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
        D365_TABLE = 'mha_title'
        AND IS_OPEN
        AND ROW_CONDITION_KEY IS NULL
),

RESOLVED AS (
    SELECT
        R.RE_TITLE,
        T.MHA_TITLEID AS D365_ID,
        G.GATE_CODES,
        R.RE_TITLE AS MHA_NAME
    FROM RE_TITLES AS R
    LEFT JOIN D365_TITLES AS T
        ON UPPER(TRIM(R.RE_TITLE)) = T.NAME_KEY
    CROSS JOIN GATES AS G
)

SELECT
    RE_TITLE,
    D365_ID,
    CASE
        WHEN D365_ID IS NOT NULL THEN 'EXISTS'
        WHEN GATE_CODES IS NOT NULL THEN 'HOLD'
        ELSE 'CREATE'
    END AS LOAD_ACTION,
    IFF(
        D365_ID IS NULL AND GATE_CODES IS NOT NULL,
        'GATE:' || GATE_CODES,
        NULL
    ) AS HOLD_REASON,
    OBJECT_CONSTRUCT('mha_name', MHA_NAME) AS PAYLOAD,
    MHA_NAME
FROM RESOLVED;