create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_CAMPAIGN(
	RE_CAMPAIGN_ID,
	RE_CAMPAIGN_CODE,
	D365_ID,
	LOAD_ACTION,
	HOLD_REASON,
	PAYLOAD,
	ACTUALEND,
	ACTUALSTART,
	CODENAME,
	DESCRIPTION,
	EXPECTEDREVENUE,
	MSNFP_CAMPAIGNCATEGORY,
	NAME,
	STATECODE,
	STATUSCODE
) as
-- One D365 campaign per RE campaign. The key is the campaign code, which D365
-- holds in codename (matched ignoring case and padding). A campaign already in
-- D365 is EXISTS and keeps its D365 id. Where D365 holds two rows of one code,
-- the oldest wins. RE_CAMPAIGN_ID is the numeric RE id that appeals use to
-- point at their campaign.
-- Status: an active RE campaign is Launched and an inactive one is Completed.
-- The status value and the state it belongs to come from the D365 metadata, and
-- are always sent together. RE start and end dates are the actual start and
-- end in D365 (date only).
WITH STATUS_MAP AS (
    SELECT
        OPTION_VALUE AS STATUSCODE,
        STATE AS STATECODE,
        UPPER(TRIM(OPTION_LABEL)) AS STATUS_LABEL
    FROM RAW.DYNAMICS.VW_ODS_METADATA_OPTIONS
    WHERE
        ENTITY_LOGICALNAME = 'campaign'
        AND ATTRIBUTE_LOGICALNAME = 'statuscode'
),

D365_CAMPAIGNS AS (
    SELECT
        UPPER(TRIM(CODENAME)) AS CODE_KEY,
        CAMPAIGNID
    FROM RAW.DYNAMICS.VW_ODS_CAMPAIGNS
    WHERE NULLIF(TRIM(CODENAME), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(CODENAME))
            ORDER BY CREATEDON, CAMPAIGNID
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
        D365_TABLE = 'campaign'
        AND IS_OPEN
        AND ROW_CONDITION_KEY IS NULL
),

MAPPED AS (
    SELECT
        C.ID AS RE_CAMPAIGN_ID,
        C.CAMPAIGNCODE AS RE_CAMPAIGN_CODE,
        D.CAMPAIGNID AS D365_ID,
        G.GATE_CODES,
        TRY_TO_DATE(LEFT(C.DATEFINISH, 10)) AS ACTUALEND,
        TRY_TO_DATE(LEFT(C.DATESTART, 10)) AS ACTUALSTART,
        NULLIF(TRIM(C.CAMPAIGNCODE), '') AS CODENAME,
        NULLIF(TRIM(C.CAMPAIGNDESCRIPTION), '') AS DESCRIPTION,
        ROUND(C.OVERALLGOAL, 2)::NUMBER(18, 2) AS EXPECTEDREVENUE,
        -- Placeholder: the category option list is not agreed, so this is
        -- never filled and never sent
        NULL::NUMBER(10, 0) AS MSNFP_CAMPAIGNCATEGORY,
        NULLIF(TRIM(C.CAMPAIGNDESCRIPTION), '') AS NAME,
        S.STATECODE,
        S.STATUSCODE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CAMPAIGNS AS C
    LEFT JOIN STATUS_MAP AS S
        ON
            S.STATUS_LABEL = CASE C.ACTIVE
                WHEN 1 THEN 'LAUNCHED'
                WHEN 0 THEN 'COMPLETED'
            END
    LEFT JOIN D365_CAMPAIGNS AS D
        ON UPPER(TRIM(C.CAMPAIGNCODE)) = D.CODE_KEY
    CROSS JOIN GATES AS G
)

SELECT
    RE_CAMPAIGN_ID,
    RE_CAMPAIGN_CODE,
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
    -- msnfp_campaigncategory is a placeholder and stays out of the body
    OBJECT_CONSTRUCT(
        'actualend', TO_CHAR(ACTUALEND, 'YYYY-MM-DD'),
        'actualstart', TO_CHAR(ACTUALSTART, 'YYYY-MM-DD'),
        'codename', CODENAME,
        'description', DESCRIPTION,
        'expectedrevenue', EXPECTEDREVENUE,
        'name', NAME,
        'statecode', STATECODE,
        'statuscode', STATUSCODE
    ) AS PAYLOAD,
    ACTUALEND,
    ACTUALSTART,
    CODENAME,
    DESCRIPTION,
    EXPECTEDREVENUE,
    MSNFP_CAMPAIGNCATEGORY,
    NAME,
    STATECODE,
    STATUSCODE
FROM MAPPED;