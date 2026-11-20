 CREATE OR REPLACE VIEW INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_APPEAL (
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
) AS

WITH SOURCE_APPEALS AS (
    SELECT
        A.*,
        COUNT(*) OVER (PARTITION BY A.ID) AS SOURCE_ID_ROWS
    FROM RAW.RAISERS_EDGE.VW_ODS_T_APPEALS A
),

D365_APPEALS AS (
    SELECT
        TRIM(MHA_SOURCEID) AS SOURCE_KEY,
        COUNT(*) AS MATCHES,
        MIN(NULLIF(TRIM(MSNFP_APPEALID), '')) AS D365_ID
    FROM RAW.DYNAMICS.VW_ODS_MSNFP_APPEALS
    WHERE NULLIF(TRIM(MHA_SOURCEID), '') IS NOT NULL
    GROUP BY TRIM(MHA_SOURCEID)
),

CAMPAIGNS AS (
    SELECT
        RE_CAMPAIGN_ID,
        COUNT(*) AS CAMPAIGN_ROWS,
        MIN(NULLIF(TRIM(D365_ID), '')) AS D365_ID
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_CAMPAIGN
    GROUP BY RE_CAMPAIGN_ID
),

GATES AS (
    SELECT
        NULLIF(
            LISTAGG(GATE_CODE, ',') WITHIN GROUP (ORDER BY GATE_CODE),
            ''
        ) AS GATE_CODES
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_REF_LOAD_GATE
    WHERE D365_TABLE = 'msnfp_appeal'
      AND IS_OPEN
      AND ROW_CONDITION_KEY IS NULL
),

-- Replace these placeholders only when the mappings and safety rules
-- have been agreed and implemented.
BUSINESS_MAPPINGS AS (
    SELECT
        A.*,
        NULL::NUMBER(18, 4) AS ESTIMATED_REVENUE,
        NULL::NUMBER AS APPEAL_STATECODE,
        NULL::NUMBER AS APPEAL_STATUSCODE,
        NULL::BOOLEAN AS NO_EXISTING_APPEAL,
        FALSE AS BUSINESS_MAPPINGS_APPROVED,
        FALSE AS DISPATCH_SAFETY_VERIFIED
    FROM SOURCE_APPEALS A
),

MAPPED AS (
    SELECT
        A.ID AS RE_APPEAL_ID,
        A.CAMPAIGNCODE AS RE_CAMPAIGN_ID,
        A.SOURCE_ID_ROWS,

        D.MATCHES AS APPEAL_MATCHES,
        D.D365_ID,

        C.CAMPAIGN_ROWS,
        C.D365_ID AS CAMPAIGN_D365_ID,

        G.GATE_CODES,

        TO_VARCHAR(A.ID) AS MHA_SOURCEID,
        C.D365_ID AS MSNFP_CAMPAIGNID,
        NULLIF(TRIM(A.CAMPAIGNDESCRIPTION), '') AS MSNFP_IDENTIFIER,

        A.ESTIMATED_REVENUE,
        A.APPEAL_STATECODE,
        A.APPEAL_STATUSCODE,
        A.NO_EXISTING_APPEAL,
        A.BUSINESS_MAPPINGS_APPROVED,
        A.DISPATCH_SAFETY_VERIFIED

    FROM BUSINESS_MAPPINGS A

    LEFT JOIN D365_APPEALS D
        ON TO_VARCHAR(A.ID) = D.SOURCE_KEY

    LEFT JOIN CAMPAIGNS C
        ON A.CAMPAIGNCODE = C.RE_CAMPAIGN_ID

    CROSS JOIN GATES G
),

REASONED AS (
    SELECT
        *,
        NULLIF(
            ARRAY_TO_STRING(
                ARRAY_CONSTRUCT_COMPACT(

                    IFF(
                        RE_APPEAL_ID IS NULL OR SOURCE_ID_ROWS <> 1,
                        'INVALID_OR_DUPLICATE_RE_ID',
                        NULL
                    ),

                    IFF(
                        APPEAL_MATCHES > 1,
                        'MULTIPLE_DYNAMICS_SOURCE_ID_MATCHES',
                        NULL
                    ),

                    IFF(
                        APPEAL_MATCHES = 1
                        AND (
                            D365_ID IS NULL
                            OR NOT REGEXP_LIKE(
                                LOWER(D365_ID),
                                '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
                            )
                        ),
                        'INVALID_DYNAMICS_APPEAL_ID',
                        NULL
                    ),

                    IFF(
                        GATE_CODES IS NOT NULL,
                        'GATE:' || GATE_CODES,
                        NULL
                    ),

                    IFF(
                        RE_CAMPAIGN_ID IS NULL,
                        'CAMPAIGN_NOT_PROVIDED',
                        NULL
                    ),

                    IFF(
                        RE_CAMPAIGN_ID IS NOT NULL
                        AND COALESCE(CAMPAIGN_ROWS, 0) > 1,
                        'MULTIPLE_CAMPAIGN_MATCHES',
                        NULL
                    ),

                    IFF(
                        RE_CAMPAIGN_ID IS NOT NULL
                        AND COALESCE(CAMPAIGN_ROWS, 0) <= 1
                        AND CAMPAIGN_D365_ID IS NULL,
                        'PARENT_MISSING:campaign',
                        NULL
                    ),

                    IFF(
                        CAMPAIGN_D365_ID IS NOT NULL
                        AND NOT REGEXP_LIKE(
                            LOWER(CAMPAIGN_D365_ID),
                            '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
                        ),
                        'INVALID_DYNAMICS_CAMPAIGN_ID',
                        NULL
                    ),

                    IFF(
                        MSNFP_IDENTIFIER IS NULL,
                        'APPEAL_NAME_MISSING',
                        NULL
                    ),

                    IFF(
                        NO_EXISTING_APPEAL IS DISTINCT FROM TRUE,
                        'EXISTING_RECORD_CHECK_PENDING',
                        NULL
                    ),

                    IFF(
                        NOT BUSINESS_MAPPINGS_APPROVED,
                        'BUSINESS_MAPPINGS_PENDING',
                        NULL
                    ),

                    IFF(
                        NOT DISPATCH_SAFETY_VERIFIED,
                        'DISPATCH_SAFETY_PENDING',
                        NULL
                    )

                ),
                ','
            ),
            ''
        ) AS PENDING_REASONS
    FROM MAPPED
)

SELECT
    RE_APPEAL_ID,
    RE_CAMPAIGN_ID,
    D365_ID,
    CAMPAIGN_D365_ID,

    CASE
        WHEN RE_APPEAL_ID IS NULL OR SOURCE_ID_ROWS <> 1 THEN 'HOLD'
        WHEN APPEAL_MATCHES > 1 THEN 'HOLD'
        WHEN APPEAL_MATCHES = 1
             AND (
                 D365_ID IS NULL
                 OR NOT REGEXP_LIKE(
                     LOWER(D365_ID),
                     '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
                 )
             ) THEN 'HOLD'
        WHEN APPEAL_MATCHES = 1 THEN 'EXISTS'
        WHEN PENDING_REASONS IS NOT NULL THEN 'HOLD'
        ELSE 'CREATE'
    END AS LOAD_ACTION,

    CASE
        WHEN RE_APPEAL_ID IS NULL OR SOURCE_ID_ROWS <> 1 THEN PENDING_REASONS
        WHEN APPEAL_MATCHES > 1 THEN PENDING_REASONS
        WHEN APPEAL_MATCHES = 1
             AND (
                 D365_ID IS NULL
                 OR NOT REGEXP_LIKE(
                     LOWER(D365_ID),
                     '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
                 )
             ) THEN PENDING_REASONS
        WHEN APPEAL_MATCHES = 1 THEN NULL
        ELSE PENDING_REASONS
    END AS HOLD_REASON,

    OBJECT_CONSTRUCT(
        'mha_source', 'Raisers Edge',
        'mha_sourceid', MHA_SOURCEID,

        'msnfp_campaignid@odata.bind', IFF(
            MSNFP_CAMPAIGNID IS NOT NULL,
            '/campaigns(' || MSNFP_CAMPAIGNID || ')',
            NULL
        ),

        'msnfp_identifier', MSNFP_IDENTIFIER,
        'msnfp_estimatedrevenue', ESTIMATED_REVENUE,
        'statecode', APPEAL_STATECODE,
        'statuscode', APPEAL_STATUSCODE
    ) AS PAYLOAD,

    MHA_SOURCEID,
    MSNFP_CAMPAIGNID,
    MSNFP_IDENTIFIER

FROM REASONED;