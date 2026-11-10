create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_APPEAL(
	RE_APPEAL_ID,
	RE_CAMPAIGN_ID,
	D365_ID,
	CAMPAIGN_D365_ID,
	LOAD_ACTION,
	HOLD_REASON,
	PAYLOAD,
	MHA_SOURCEID,
	MSNFP_CAMPAIGNID,
	MSNFP_IDENTIFIER
) as
-- One D365 appeal per RE appeal. The key is the RE appeal id, which D365 holds
-- in mha_sourceid. An appeal already in D365 is EXISTS and keeps its D365 id.
-- Where D365 holds two rows of one id, the oldest wins.
-- Campaign: the appeal points at its RE campaign by the campaign's numeric id.
-- The D365 campaign id comes from VW_D365_CAMPAIGN, so a campaign D365 already
-- held binds the same way as a new one. An appeal with a campaign that has no
-- D365 id yet is held with PARENT_MISSING:campaign. An appeal with no campaign
-- loads without one.
WITH D365_APPEALS AS (
    SELECT
        TRIM(MHA_SOURCEID) AS SOURCE_KEY,
        MSNFP_APPEALID
    FROM RAW.DYNAMICS.VW_ODS_MSNFP_APPEALS
    WHERE NULLIF(TRIM(MHA_SOURCEID), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(MHA_SOURCEID)
            ORDER BY CREATEDON, MSNFP_APPEALID
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
        D365_TABLE = 'msnfp_appeal'
        AND IS_OPEN
        AND ROW_CONDITION_KEY IS NULL
),

MAPPED AS (
    SELECT
        A.ID AS RE_APPEAL_ID,
        A.CAMPAIGNCODE AS RE_CAMPAIGN_ID,
        D.MSNFP_APPEALID AS D365_ID,
        C.D365_ID AS CAMPAIGN_D365_ID,
        G.GATE_CODES,
        A.ID::VARCHAR AS MHA_SOURCEID,
        C.D365_ID AS MSNFP_CAMPAIGNID,
        -- The RE column named CAMPAIGNDESCRIPTION holds the appeal description
        NULLIF(TRIM(A.CAMPAIGNDESCRIPTION), '') AS MSNFP_IDENTIFIER
    FROM RAW.RAISERS_EDGE.VW_ODS_T_APPEALS AS A
    LEFT JOIN INTEGRATION_DB.DYNAMICS.VW_D365_CAMPAIGN AS C
        ON A.CAMPAIGNCODE = C.RE_CAMPAIGN_ID
    LEFT JOIN D365_APPEALS AS D
        ON A.ID::VARCHAR = D.SOURCE_KEY
    CROSS JOIN GATES AS G
)

SELECT
    RE_APPEAL_ID,
    RE_CAMPAIGN_ID,
    D365_ID,
    CAMPAIGN_D365_ID,
    CASE
        WHEN D365_ID IS NOT NULL THEN 'EXISTS'
        WHEN GATE_CODES IS NOT NULL THEN 'HOLD'
        WHEN RE_CAMPAIGN_ID IS NOT NULL AND CAMPAIGN_D365_ID IS NULL THEN 'HOLD'
        ELSE 'CREATE'
    END AS LOAD_ACTION,
    CASE
        WHEN D365_ID IS NOT NULL THEN NULL
        WHEN GATE_CODES IS NOT NULL THEN 'GATE:' || GATE_CODES
        WHEN
            RE_CAMPAIGN_ID IS NOT NULL AND CAMPAIGN_D365_ID IS NULL
            THEN 'PARENT_MISSING:campaign'
    END AS HOLD_REASON,
    OBJECT_CONSTRUCT(
        'mha_sourceid', MHA_SOURCEID,
        -- lookup: navigation property with @odata.bind, never the plain key
        'msnfp_campaignid@odata.bind', IFF(
            MSNFP_CAMPAIGNID IS NOT NULL,
            '/campaigns(' || MSNFP_CAMPAIGNID || ')',
            NULL
        ),
        'msnfp_identifier', MSNFP_IDENTIFIER
    ) AS PAYLOAD,
    MHA_SOURCEID,
    MSNFP_CAMPAIGNID,
    MSNFP_IDENTIFIER
FROM MAPPED;