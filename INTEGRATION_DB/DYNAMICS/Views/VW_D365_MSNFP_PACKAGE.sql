create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_PACKAGE(
	RE_PACKAGE_ID,
	RE_APPEAL_ID,
	D365_ID,
	MSNFP_APPEAL_D365_ID,
	LOAD_ACTION,
	HOLD_REASON,
	PAYLOAD,
	MHA_SOURCEID,
	MHNAS_NUMBERSOLICITED,
	MHNAS_PACKAGECODE,
	MSNFP_APPEALID,
	MSNFP_IDENTIFIER
) as
-- One D365 package per RE package. The key is the RE package id, which D365
-- holds in mha_sourceid. The package reference is not a key: RE repeats it
-- across appeals. A package already in D365 is EXISTS and keeps its D365 id.
-- Where D365 holds two rows of one id, the oldest wins.
-- Appeal: the D365 appeal id comes from VW_D365_MSNFP_APPEAL, so an appeal
-- D365 already held binds the same way as a new one. A package whose appeal
-- has no D365 id yet is held with PARENT_MISSING:msnfp_appeal.
WITH D365_PACKAGES AS (
    SELECT
        TRIM(MHA_SOURCEID) AS SOURCE_KEY,
        MSNFP_PACKAGEID
    FROM RAW.DYNAMICS.VW_ODS_MSNFP_PACKAGES
    WHERE NULLIF(TRIM(MHA_SOURCEID), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(MHA_SOURCEID)
            ORDER BY CREATEDON, MSNFP_PACKAGEID
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
        D365_TABLE = 'msnfp_package'
        AND IS_OPEN
        AND ROW_CONDITION_KEY IS NULL
),

MAPPED AS (
    SELECT
        P.ID AS RE_PACKAGE_ID,
        P.APPEALID AS RE_APPEAL_ID,
        D.MSNFP_PACKAGEID AS D365_ID,
        A.D365_ID AS MSNFP_APPEAL_D365_ID,
        G.GATE_CODES,
        P.ID::VARCHAR AS MHA_SOURCEID,
        -- Placeholder: D365 has no number solicited field on packages yet, so
        -- this is never filled and never sent
        NULL::NUMBER(10, 0) AS MHNAS_NUMBERSOLICITED,
        NULLIF(TRIM(P.PACKAGEREF), '') AS MHNAS_PACKAGECODE,
        A.D365_ID AS MSNFP_APPEALID,
        NULLIF(TRIM(P.DESCRIPTION), '') AS MSNFP_IDENTIFIER
    FROM RAW.RAISERS_EDGE.VW_ODS_T_PACKAGES AS P
    LEFT JOIN INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_APPEAL AS A
        ON P.APPEALID = A.RE_APPEAL_ID
    LEFT JOIN D365_PACKAGES AS D
        ON P.ID::VARCHAR = D.SOURCE_KEY
    CROSS JOIN GATES AS G
)

SELECT
    RE_PACKAGE_ID,
    RE_APPEAL_ID,
    D365_ID,
    MSNFP_APPEAL_D365_ID,
    CASE
        WHEN D365_ID IS NOT NULL THEN 'EXISTS'
        WHEN GATE_CODES IS NOT NULL THEN 'HOLD'
        WHEN
            RE_APPEAL_ID IS NOT NULL AND MSNFP_APPEAL_D365_ID IS NULL
            THEN 'HOLD'
        ELSE 'CREATE'
    END AS LOAD_ACTION,
    CASE
        WHEN D365_ID IS NOT NULL THEN NULL
        WHEN GATE_CODES IS NOT NULL THEN 'GATE:' || GATE_CODES
        WHEN
            RE_APPEAL_ID IS NOT NULL AND MSNFP_APPEAL_D365_ID IS NULL
            THEN 'PARENT_MISSING:msnfp_appeal'
    END AS HOLD_REASON,
    -- mhnas_numbersolicited is a placeholder and stays out of the body
    OBJECT_CONSTRUCT(
        'mha_sourceid', MHA_SOURCEID,
        'mhnas_packagecode', MHNAS_PACKAGECODE,
        -- lookup: navigation property with @odata.bind, never the plain key
        'msnfp_AppealId@odata.bind', IFF(
            MSNFP_APPEALID IS NOT NULL,
            '/msnfp_appeals(' || MSNFP_APPEALID || ')',
            NULL
        ),
        'msnfp_identifier', MSNFP_IDENTIFIER
    ) AS PAYLOAD,
    MHA_SOURCEID,
    MHNAS_NUMBERSOLICITED,
    MHNAS_PACKAGECODE,
    MSNFP_APPEALID,
    MSNFP_IDENTIFIER
FROM MAPPED;