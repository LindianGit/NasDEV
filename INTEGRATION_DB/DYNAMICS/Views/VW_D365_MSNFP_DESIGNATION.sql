create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_DESIGNATION(
	RE_FUND_ID,
	RE_FUND_CODE,
	D365_ID,
	LOAD_ACTION,
	HOLD_REASON,
	PAYLOAD,
	MHA_SOURCEID,
	MSNFP_DESIGNATIONCODE,
	MSNFP_DESIGNATIONGROUP,
	MSNFP_ENDDATE,
	MSNFP_NAME,
	MSNFP_RESTRICTIONTYPE,
	MSNFP_STARTDATE,
	STATECODE,
	STATUSCODE,
	TBC_RESTRICTIONCATEGORY
) as
-- One D365 designation per RE fund. The key is the fund code, which D365
-- holds in msnfp_designationcode (matched ignoring case and padding), because
-- designations already in D365 carry no RE id. A designation already in D365 is
-- EXISTS and keeps its D365 id. Where D365 holds two rows of one code, the
-- oldest wins. mha_sourceid carries the RE fund id, the same value that gift
-- lines and regular giving hold.
-- State: an active RE fund is Active and an inactive one is Inactive. The
-- status is the default status of that state, from the D365 metadata, and both
-- are always sent together.
-- Restriction type: a restricted fund is Restricted and any other is
-- Unrestricted.
WITH STATE_MAP AS (
    SELECT
        OPTION_VALUE AS STATECODE,
        DEFAULT_STATUS AS STATUSCODE
    FROM RAW.DYNAMICS.VW_ODS_METADATA_OPTIONS
    WHERE
        ENTITY_LOGICALNAME = 'msnfp_designation'
        AND ATTRIBUTE_LOGICALNAME = 'statecode'
),

D365_DESIGNATIONS AS (
    SELECT
        UPPER(TRIM(MSNFP_DESIGNATIONCODE)) AS CODE_KEY,
        MSNFP_DESIGNATIONID
    FROM RAW.DYNAMICS.VW_ODS_MSNFP_DESIGNATIONS
    WHERE NULLIF(TRIM(MSNFP_DESIGNATIONCODE), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(MSNFP_DESIGNATIONCODE))
            ORDER BY CREATEDON, MSNFP_DESIGNATIONID
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
        D365_TABLE = 'msnfp_designation'
        AND IS_OPEN
        AND ROW_CONDITION_KEY IS NULL
),

MAPPED AS (
    SELECT
        F.ID AS RE_FUND_ID,
        F.FUNDCODE AS RE_FUND_CODE,
        D.MSNFP_DESIGNATIONID AS D365_ID,
        G.GATE_CODES,
        F.ID::VARCHAR AS MHA_SOURCEID,
        NULLIF(TRIM(F.FUNDCODE), '') AS MSNFP_DESIGNATIONCODE,
        NULLIF(TRIM(F.FUNDCATEGORYDESCRIPTION), '') AS MSNFP_DESIGNATIONGROUP,
        TRY_TO_DATE(LEFT(F.DATEFINISH, 10)) AS MSNFP_ENDDATE,
        NULLIF(TRIM(F.FUNDDESCRIPTION), '') AS MSNFP_NAME,
        CASE F.ISRESTRICTED
            WHEN TRUE THEN 831250002
            WHEN FALSE THEN 831250001
        END AS MSNFP_RESTRICTIONTYPE,
        TRY_TO_DATE(LEFT(F.DATESTART, 10)) AS MSNFP_STARTDATE,
        S.STATECODE,
        S.STATUSCODE,
        -- Placeholder: D365 has no restriction category field yet, so this
        -- is never filled and never sent
        NULL::VARCHAR AS TBC_RESTRICTIONCATEGORY
    FROM RAW.RAISERS_EDGE.VW_ODS_T_FUNDS AS F
    LEFT JOIN STATE_MAP AS S
        ON
            S.STATECODE = CASE F.ACTIVE
                WHEN 1 THEN 0
                WHEN 0 THEN 1
            END
    LEFT JOIN D365_DESIGNATIONS AS D
        ON UPPER(TRIM(F.FUNDCODE)) = D.CODE_KEY
    CROSS JOIN GATES AS G
)

SELECT
    RE_FUND_ID,
    RE_FUND_CODE,
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
    -- tbc_restrictioncategory is a placeholder and stays out of the body
    OBJECT_CONSTRUCT(
        'mha_sourceid', MHA_SOURCEID,
        'msnfp_designationcode', MSNFP_DESIGNATIONCODE,
        'msnfp_designationgroup', MSNFP_DESIGNATIONGROUP,
        'msnfp_enddate', TO_CHAR(MSNFP_ENDDATE, 'YYYY-MM-DD'),
        'msnfp_name', MSNFP_NAME,
        'msnfp_restrictiontype', MSNFP_RESTRICTIONTYPE,
        'msnfp_startdate', TO_CHAR(MSNFP_STARTDATE, 'YYYY-MM-DD'),
        'statecode', STATECODE,
        'statuscode', STATUSCODE
    ) AS PAYLOAD,
    MHA_SOURCEID,
    MSNFP_DESIGNATIONCODE,
    MSNFP_DESIGNATIONGROUP,
    MSNFP_ENDDATE,
    MSNFP_NAME,
    MSNFP_RESTRICTIONTYPE,
    MSNFP_STARTDATE,
    STATECODE,
    STATUSCODE,
    TBC_RESTRICTIONCATEGORY
FROM MAPPED;