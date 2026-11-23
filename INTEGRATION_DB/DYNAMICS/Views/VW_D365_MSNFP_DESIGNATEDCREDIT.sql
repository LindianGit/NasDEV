CREATE OR REPLACE VIEW INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_DESIGNATEDCREDIT AS

WITH SOURCE_SPLITS AS (
    SELECT
        S.ID AS RE_SPLIT_ID,
        S.GIFTID AS RE_GIFT_ID,
        S.CONSTITUENT_ID AS RE_CONSTITUENT_ID,
        S.FUNDCODE AS RE_FUND_ID,
        S.CAMPAIGNCODE AS RE_CAMPAIGN_ID,
        S.APPEALCODE AS RE_APPEAL_ID,
        S.PACKAGECODE AS RE_PACKAGE_ID,
        S.AMOUNT AS RE_SPLIT_AMOUNT,
        COUNT(*) OVER (PARTITION BY S.ID) AS SPLIT_ID_ROWS
    FROM RAW.RAISERS_EDGE.VW_ODS_T_GIFTSPLITS AS S
),

-- Aggregate first so duplicate parent rows do not multiply split rows.
PARENTS AS (
    SELECT
        RE_GIFT_ID,
        COUNT(*) AS PARENT_ROWS,
        MIN(D365_TARGET) AS PARENT_TARGET,
        MIN(LOAD_ACTION) AS PARENT_LOAD_ACTION
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_TRANSACTION
    WHERE RE_GIFT_ID IS NOT NULL
    GROUP BY RE_GIFT_ID
),

PARENT_XREFS AS (
    SELECT
        GOLDEN_RECORD_ID,
        COUNT(*) AS XREF_ROWS,
        MIN(NULLIF(TRIM(SOURCE_RECORD_ID), '')) AS CANDIDATE_ID
    FROM MDM_DB.GOLD.XREF
    WHERE SOURCE_SYSTEM = 'DYNAMICS'
      AND GOLDEN_RECORD_ID LIKE 'TRANSACTION:%'
    GROUP BY GOLDEN_RECORD_ID
),

DESIGNATION_CODE_MATCHES AS (
    SELECT
        UPPER(TRIM(MSNFP_DESIGNATIONCODE)) AS CODE_KEY,
        COUNT(*) AS D365_CODE_ROWS
    FROM RAW.DYNAMICS.VW_ODS_MSNFP_DESIGNATIONS
    WHERE NULLIF(TRIM(MSNFP_DESIGNATIONCODE), '') IS NOT NULL
    GROUP BY UPPER(TRIM(MSNFP_DESIGNATIONCODE))
),

-- A designation ID is usable only when exactly one row resolves.
DESIGNATIONS AS (
    SELECT
        D.RE_FUND_ID,
        COUNT(*) AS DESIGNATION_ROWS,
        MIN(NULLIF(TRIM(D.D365_ID), '')) AS D365_ID,
        MAX(COALESCE(C.D365_CODE_ROWS, 0)) AS D365_CODE_ROWS
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_DESIGNATION AS D
    LEFT JOIN DESIGNATION_CODE_MATCHES AS C
        ON UPPER(TRIM(D.RE_FUND_CODE)) = C.CODE_KEY
    WHERE D.RE_FUND_ID IS NOT NULL
    GROUP BY D.RE_FUND_ID
),

GATES AS (
    SELECT
        NULLIF(
            LISTAGG(GATE_CODE, ',') WITHIN GROUP (ORDER BY GATE_CODE),
            ''
        ) AS GATE_CODES
    FROM INTEGRATION_DB.DYNAMICS.VW_D365_REF_LOAD_GATE
    WHERE D365_TABLE = 'msnfp_designatedcredit'
      AND IS_OPEN
      AND ROW_CONDITION_KEY IS NULL
),

MAPPED AS (
    SELECT
        S.*,

        COALESCE(P.PARENT_ROWS, 0) AS PARENT_ROWS,
        P.PARENT_TARGET,
        P.PARENT_LOAD_ACTION,
        COALESCE(X.XREF_ROWS, 0) AS PARENT_XREF_ROWS,
        X.CANDIDATE_ID AS CANDIDATE_TRANSACTION_ID,

        COALESCE(D.DESIGNATION_ROWS, 0) AS DESIGNATION_ROWS,
        D.D365_ID AS CANDIDATE_DESIGNATION_ID,
        COALESCE(D.D365_CODE_ROWS, 0) AS D365_CODE_ROWS,

        G.GATE_CODES

    FROM SOURCE_SPLITS AS S
    LEFT JOIN PARENTS AS P
        ON S.RE_GIFT_ID = P.RE_GIFT_ID
    LEFT JOIN PARENT_XREFS AS X
        ON X.GOLDEN_RECORD_ID = 'TRANSACTION:' || TO_VARCHAR(S.RE_GIFT_ID)
    LEFT JOIN DESIGNATIONS AS D
        ON S.RE_FUND_ID = D.RE_FUND_ID
    CROSS JOIN GATES AS G
),

RESOLVED AS (
    SELECT
        *,
        CASE
            WHEN PARENT_XREF_ROWS = 1
             AND REGEXP_LIKE(
                 LOWER(CANDIDATE_TRANSACTION_ID),
                 '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
             )
                THEN CANDIDATE_TRANSACTION_ID
        END AS TRANSACTION_D365_ID,
        CASE
            WHEN DESIGNATION_ROWS = 1
             AND D365_CODE_ROWS = 1
             AND REGEXP_LIKE(
                 LOWER(CANDIDATE_DESIGNATION_ID),
                 '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
             )
                THEN CANDIDATE_DESIGNATION_ID
        END AS DESIGNATION_D365_ID
    FROM MAPPED
)

SELECT
    RE_SPLIT_ID,
    RE_GIFT_ID,
    RE_CONSTITUENT_ID,
    RE_FUND_ID,
    RE_CAMPAIGN_ID,
    RE_APPEAL_ID,
    RE_PACKAGE_ID,
    RE_SPLIT_AMOUNT,

    PARENT_ROWS,
    PARENT_TARGET,
    PARENT_LOAD_ACTION,

    TRANSACTION_D365_ID,
    DESIGNATION_D365_ID,

    'HOLD' AS LOAD_ACTION,

    ARRAY_TO_STRING(
        ARRAY_CONSTRUCT_COMPACT(
            'MAPPING_AND_DISPATCH_SAFETY_PENDING',
            'EXISTING_LINE_CHECK_PENDING',
            'GIFT_AID_RULES_PENDING',
            'AMOUNT_AND_ROUNDING_RULES_PENDING',

            IFF(
                RE_SPLIT_ID IS NULL,
                'SPLIT_ID_MISSING',
                NULL
            ),

            IFF(
                RE_SPLIT_ID IS NOT NULL AND SPLIT_ID_ROWS <> 1,
                'DUPLICATE_SPLIT_ID',
                NULL
            ),

            IFF(
                RE_GIFT_ID IS NULL,
                'PARENT_GIFT_ID_MISSING',
                NULL
            ),

            IFF(
                RE_GIFT_ID IS NOT NULL AND PARENT_ROWS = 0,
                'PARENT_NOT_IN_TRANSACTION_VIEW',
                NULL
            ),

            IFF(
                PARENT_ROWS > 1,
                'MULTIPLE_PARENT_GIFT_ROWS',
                NULL
            ),

            IFF(
                PARENT_ROWS = 1 AND PARENT_TARGET IS DISTINCT FROM 'TRANSACTION',
                'PARENT_TRANSACTION_TYPE_UNCONFIRMED',
                NULL
            ),

            IFF(
                PARENT_ROWS = 1 AND PARENT_LOAD_ACTION = 'HOLD',
                'PARENT_TRANSACTION_HELD',
                NULL
            ),

            IFF(PARENT_XREF_ROWS = 0, 'PARENT_TRANSACTION_ID_MISSING', NULL),

            IFF(PARENT_XREF_ROWS > 1, 'MULTIPLE_PARENT_TRANSACTION_IDS', NULL),

            IFF(
                PARENT_XREF_ROWS = 1 AND TRANSACTION_D365_ID IS NULL,
                'INVALID_PARENT_TRANSACTION_ID',
                NULL
            ),

            IFF(
                RE_SPLIT_AMOUNT IS NULL,
                'SPLIT_AMOUNT_MISSING',
                NULL
            ),

            IFF(
                RE_FUND_ID IS NULL,
                'FUND_ID_MISSING',
                NULL
            ),

            IFF(
                RE_FUND_ID IS NOT NULL AND DESIGNATION_ROWS = 0,
                'DESIGNATION_NOT_FOUND',
                NULL
            ),

            IFF(
                DESIGNATION_ROWS > 1,
                'MULTIPLE_DESIGNATION_ROWS',
                NULL
            ),

            IFF(
                D365_CODE_ROWS > 1,
                'MULTIPLE_D365_DESIGNATIONS_FOR_CODE',
                NULL
            ),

            IFF(
                DESIGNATION_ROWS = 1 AND CANDIDATE_DESIGNATION_ID IS NULL,
                'D365_DESIGNATION_ID_MISSING',
                NULL
            ),

            IFF(
                DESIGNATION_ROWS = 1
                AND CANDIDATE_DESIGNATION_ID IS NOT NULL
                AND D365_CODE_ROWS = 1
                AND DESIGNATION_D365_ID IS NULL,
                'INVALID_D365_DESIGNATION_ID',
                NULL
            ),

            IFF(
                GATE_CODES IS NOT NULL,
                'GATE:' || GATE_CODES,
                NULL
            )
        ),
        ','
    ) AS HOLD_REASON,

    NULL::VARIANT AS PAYLOAD,

    -- Preview only; not a complete or dispatchable Dataverse payload.
    OBJECT_CONSTRUCT(
        'msnfp_dataentryreference', TO_VARCHAR(RE_SPLIT_ID),
        'msnfp_amount', RE_SPLIT_AMOUNT,
        'msnfp_transactionid@odata.bind',
            IFF(TRANSACTION_D365_ID IS NOT NULL,
                '/msnfp_transactions(' || TRANSACTION_D365_ID || ')', NULL),
        'msnfp_designatiedcredit_designationId@odata.bind',
            IFF(DESIGNATION_D365_ID IS NOT NULL,
                '/msnfp_designations(' || DESIGNATION_D365_ID || ')', NULL)
    ) AS DRAFT_PAYLOAD

FROM RESOLVED;