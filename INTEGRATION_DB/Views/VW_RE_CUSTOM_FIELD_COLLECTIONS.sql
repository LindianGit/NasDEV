create or replace view INTEGRATION_DB.RAISERS_EDGE.VW_RE_CUSTOM_FIELD_COLLECTIONS(
	GOLDEN_RECORD_ID,
	CONSTITUENT_ID,
	FIELDS
) as
-- Emits one row per constituent for POST /customfieldcollection when new
-- CodeTableEntry custom field categories have no existing RE record.
-- Only Licensed User Type is included.  Work Sector (multi-value) and all
-- Text-type categories are excluded: their value format is unconfirmed for the
-- collection endpoint and a single bad element poisons the entire array.
-- Output columns: GOLDEN_RECORD_ID, CONSTITUENT_ID, FIELDS.

WITH WINNER AS (
    SELECT
        GOLDEN_RECORD_ID,
        CONSTITUENT_ID,
        LICENCED_USER_TYPE
    FROM INTEGRATION_DB.RAISERS_EDGE.VW_ENRICHED
    WHERE CONSTITUENT_ID IS NOT NULL
),

RE_ATTRS AS (
    SELECT
        CONSTITUENT_ID,
        MAX(CASE WHEN ATTRIBUTENAME = 'Licensed User Type' THEN ID END)
            AS LICENCED_USER_TYPE_ID
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES
    WHERE ATTRIBUTENAME = 'Licensed User Type'
    GROUP BY CONSTITUENT_ID
),

CANDIDATE AS (
    SELECT
        W.GOLDEN_RECORD_ID,
        W.CONSTITUENT_ID,
        ARRAY_CONSTRUCT_COMPACT(
            IFF(
                RA.LICENCED_USER_TYPE_ID IS NULL
                AND NULLIF(TRIM(W.LICENCED_USER_TYPE), '') IS NOT NULL,
                OBJECT_CONSTRUCT(
                    'category', 'Licensed User Type',
                    'value', OBJECT_CONSTRUCT(
                        'description', NULLIF(TRIM(W.LICENCED_USER_TYPE), '')
                    )
                ),
                NULL
            )
        ) AS FIELDS
    FROM WINNER AS W
    LEFT JOIN RE_ATTRS AS RA ON W.CONSTITUENT_ID = RA.CONSTITUENT_ID
)

SELECT
    GOLDEN_RECORD_ID,
    CONSTITUENT_ID,
    FIELDS
FROM CANDIDATE
WHERE ARRAY_SIZE(FIELDS) > 0;