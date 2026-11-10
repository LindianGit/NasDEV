create or replace view INTEGRATION_DB.RAISERS_EDGE.VW_RE_CUSTOM_FIELDS(
	GOLDEN_RECORD_ID,
	CONSTITUENT_ID,
	ACTION,
	CUSTOM_FIELD_ID,
	PAYLOAD
) as
-- Non-consent custom field writeback (2B). Re-based on GOLDEN_RECORDS.
-- Desired state sourced from golden attribute columns (LICENCED_USER_TYPE,
-- PROFESSIONAL_WORK_SECTOR, JOB_TITLE, LEGACY_*).
-- Current RE state: RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES.
-- Scope gates: FOUR_YEAR = TRUE, IS_GDPR_SUPPRESSED = FALSE,
--              RE_CONSTITUENT_ID IS NOT NULL.
--
-- Emits one row per (golden_record_id, category):
--   POST  when no existing RE attribute record
--         (parent_id in body links field to constituent)
--   PATCH when a record exists and the winner value is absent from all
--         RE rows for that (constituent, category); targets the
--         highest-id row (canonical PATCH target)
--   Suppress when winner value is already held on any RE row for that
--         (constituent, category), preventing no-op writes
--
-- Category-to-value-type mapping:
--   Licensed User Type         -> CodeTableEntry -> value: {description: "..."}
--   Professional - Work Sector -> CodeTableEntry -> value: {description: "..."}
--   Professional - Job Title   -> Text           -> value: "..."
--   Legacy Intender            -> Text           -> value: "<value>"
--   Legacy Pledger             -> Text           -> value: "<value>"
--   Legacy Considerer          -> Text           -> value: "<value>"
--   Legacy Enquirer            -> Text           -> value: "<value>"

WITH WINNER AS (
    SELECT
        GR.GOLDEN_RECORD_ID,
        IDS.RE_CONSTITUENT_ID AS CONSTITUENT_ID,
        GR.LICENCED_USER_TYPE,
        GR.PROFESSIONAL_WORK_SECTOR,
        GR.JOB_TITLE,
        GR.LEGACY_INTENDER,
        GR.LEGACY_PLEDGER,
        GR.LEGACY_CONSIDERER,
        GR.LEGACY_ENQUIRER
    FROM MDM_DB.GOLD.GOLDEN_RECORDS AS GR
    INNER JOIN MDM_DB.GOLD.VW_GOLDEN_RECORD_IDS AS IDS
        ON GR.GOLDEN_RECORD_ID = IDS.GOLDEN_RECORD_ID
    WHERE
        GR._IS_ACTIVE = TRUE
        AND IDS.IS_GDPR_SUPPRESSED = FALSE
        AND GR.FOUR_YEAR = TRUE
        AND IDS.RE_CONSTITUENT_ID IS NOT NULL
),

RE_ATTRS AS (
    -- Canonical highest-id row per (constituent, category).
    -- MAX(ID) per group equals ROW_NUMBER OVER (ORDER BY ID DESC) = 1.
    -- Values are not selected here; existence suppression uses RE_ATTRS_EXISTS.
    SELECT
        CONSTITUENT_ID,
        MAX(CASE WHEN ATTRIBUTENAME = 'Licensed User Type' THEN ID END)
            AS LICENCED_USER_TYPE_ID,
        MAX(CASE WHEN ATTRIBUTENAME = 'Professional - Job Title' THEN ID END)
            AS JOB_TITLE_ID,
        MAX(CASE WHEN ATTRIBUTENAME = 'Legacy Intender' THEN ID END)
            AS LEGACY_INTENDER_ID,
        MAX(CASE WHEN ATTRIBUTENAME = 'Legacy Pledger' THEN ID END)
            AS LEGACY_PLEDGER_ID,
        MAX(CASE WHEN ATTRIBUTENAME = 'Legacy Considerer' THEN ID END)
            AS LEGACY_CONSIDERER_ID,
        MAX(CASE WHEN ATTRIBUTENAME = 'Legacy Enquirer' THEN ID END)
            AS LEGACY_ENQUIRER_ID
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES
    WHERE
        ATTRIBUTENAME IN (
            'Licensed User Type',
            'Professional - Job Title',
            'Legacy Intender',
            'Legacy Pledger',
            'Legacy Considerer',
            'Legacy Enquirer'
        )
    GROUP BY CONSTITUENT_ID
),

RE_ATTRS_EXISTS AS (
    -- All trimmed values held per (constituent, category) across every row.
    -- Joined per branch with category-specific normalisation (Job Title
    -- case-insensitive; others exact) to detect whether the winner is
    -- already present.  A match suppresses the row; no match allows PATCH.
    SELECT DISTINCT
        CONSTITUENT_ID,
        ATTRIBUTENAME,
        NULLIF(TRIM(ATTRIBUTEVALUE), '') AS ATTR_VALUE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES
    WHERE
        ATTRIBUTENAME IN (
            'Licensed User Type',
            'Professional - Job Title',
            'Legacy Intender',
            'Legacy Pledger',
            'Legacy Considerer',
            'Legacy Enquirer'
        )
        AND NULLIF(TRIM(ATTRIBUTEVALUE), '') IS NOT NULL
),

-- Work Sector is multi-value: golden PROFESSIONAL_WORK_SECTOR is a ';'-joined
-- set and RE stores one attribute row per sector.  Explode the golden set to
-- one row per (constituent, sector), de-duplicated case-insensitively.
GOLDEN_WORK_SECTOR AS (
    SELECT
        W.GOLDEN_RECORD_ID,
        W.CONSTITUENT_ID,
        TRIM(S.VALUE) AS SECTOR,
        LOWER(TRIM(S.VALUE)) AS SECTOR_NORM
    FROM WINNER AS W,
        LATERAL SPLIT_TO_TABLE(W.PROFESSIONAL_WORK_SECTOR, ';') AS S
    WHERE NULLIF(TRIM(S.VALUE), '') IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY W.CONSTITUENT_ID, LOWER(TRIM(S.VALUE))
        ORDER BY TRIM(S.VALUE)
    ) = 1
),

-- Every Work Sector value already held against the constituent, normalised.
RE_WORK_SECTOR AS (
    SELECT DISTINCT
        CONSTITUENT_ID,
        LOWER(TRIM(ATTRIBUTEVALUE)) AS SECTOR_NORM
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES
    WHERE
        ATTRIBUTENAME = 'Professional - Work Sector'
        AND NULLIF(TRIM(ATTRIBUTEVALUE), '') IS NOT NULL
)

-- Licensed User Type (CodeTableEntry)
-- Existence gate: suppress when winner (exact) already held on any RE row.
SELECT
    W.GOLDEN_RECORD_ID,
    W.CONSTITUENT_ID,
    IFF(RA.LICENCED_USER_TYPE_ID IS NULL, 'POST', 'PATCH') AS ACTION,
    RA.LICENCED_USER_TYPE_ID::VARCHAR AS CUSTOM_FIELD_ID,
    CASE
        WHEN RA.LICENCED_USER_TYPE_ID IS NULL
            THEN OBJECT_CONSTRUCT(
                'parent_id', W.CONSTITUENT_ID,
                'category', 'Licensed User Type',
                'value', OBJECT_CONSTRUCT(
                    'description', NULLIF(TRIM(W.LICENCED_USER_TYPE), '')
                )
            )
        ELSE OBJECT_CONSTRUCT(
            'value', OBJECT_CONSTRUCT(
                'description', NULLIF(TRIM(W.LICENCED_USER_TYPE), '')
            )
        )
    END AS PAYLOAD
FROM WINNER AS W
LEFT JOIN RE_ATTRS AS RA ON W.CONSTITUENT_ID = RA.CONSTITUENT_ID
LEFT JOIN RE_ATTRS_EXISTS AS RE_EXISTS
    ON
        W.CONSTITUENT_ID = RE_EXISTS.CONSTITUENT_ID
        AND RE_EXISTS.ATTRIBUTENAME = 'Licensed User Type'
        AND RE_EXISTS.ATTR_VALUE = NULLIF(TRIM(W.LICENCED_USER_TYPE), '')
WHERE
    NULLIF(TRIM(W.LICENCED_USER_TYPE), '') IS NOT NULL
    AND (
        RA.LICENCED_USER_TYPE_ID IS NULL         -- POST: no row exists
        -- PATCH: winner absent from all rows
        OR RE_EXISTS.CONSTITUENT_ID IS NULL
    )

UNION ALL

-- Professional - Work Sector (CodeTableEntry) — multi-value, POST only.
-- Golden PROFESSIONAL_WORK_SECTOR is a ';'-joined set; RE stores one attribute
-- row per sector.  Each winning sector absent from RE is created as its own
-- single CodeTableEntry.  No PATCH is emitted: a joined multi-value string is
-- not a valid single CodeTableEntry value, and sectors are added as discrete
-- rows rather than patched in place.  Existing sectors are suppressed
-- (case-insensitive) so no duplicate POST is issued.  Removal of sectors no
-- longer desired is out of scope (tighten-safe; RE owns deletion).
SELECT
    G.GOLDEN_RECORD_ID,
    G.CONSTITUENT_ID,
    'POST' AS ACTION,
    NULL::VARCHAR AS CUSTOM_FIELD_ID,
    OBJECT_CONSTRUCT(
        'parent_id', G.CONSTITUENT_ID,
        'category', 'Professional - Work Sector',
        'value', OBJECT_CONSTRUCT('description', G.SECTOR)
    ) AS PAYLOAD
FROM GOLDEN_WORK_SECTOR AS G
LEFT JOIN RE_WORK_SECTOR AS R
    ON
        G.CONSTITUENT_ID = R.CONSTITUENT_ID
        AND G.SECTOR_NORM = R.SECTOR_NORM
WHERE R.SECTOR_NORM IS NULL

UNION ALL

-- Professional - Job Title (Text)
-- Existence gate: suppress when winner (case-insensitive) is already held.
SELECT
    W.GOLDEN_RECORD_ID,
    W.CONSTITUENT_ID,
    IFF(RA.JOB_TITLE_ID IS NULL, 'POST', 'PATCH') AS ACTION,
    RA.JOB_TITLE_ID::VARCHAR AS CUSTOM_FIELD_ID,
    CASE
        WHEN RA.JOB_TITLE_ID IS NULL
            THEN OBJECT_CONSTRUCT(
                'parent_id', W.CONSTITUENT_ID,
                'category', 'Professional - Job Title',
                'value', NULLIF(TRIM(W.JOB_TITLE), '')
            )
        ELSE OBJECT_CONSTRUCT('value', NULLIF(TRIM(W.JOB_TITLE), ''))
    END AS PAYLOAD
FROM WINNER AS W
LEFT JOIN RE_ATTRS AS RA ON W.CONSTITUENT_ID = RA.CONSTITUENT_ID
LEFT JOIN RE_ATTRS_EXISTS AS RE_EXISTS
    ON
        W.CONSTITUENT_ID = RE_EXISTS.CONSTITUENT_ID
        AND RE_EXISTS.ATTRIBUTENAME = 'Professional - Job Title'
        -- Free-text: compare case-insensitively so cosmetic casing differences
        -- do not fire a no-op PATCH.  Payload sends the winner value verbatim.
        AND LOWER(RE_EXISTS.ATTR_VALUE) = LOWER(NULLIF(TRIM(W.JOB_TITLE), ''))
WHERE
    NULLIF(TRIM(W.JOB_TITLE), '') IS NOT NULL
    AND (
        RA.JOB_TITLE_ID IS NULL               -- POST: no row exists
        -- PATCH: winner absent from all rows
        OR RE_EXISTS.CONSTITUENT_ID IS NULL
    )

UNION ALL

-- Legacy Intender (Text)
-- Existence gate: suppress when winner (exact) already held on any RE row.
SELECT
    W.GOLDEN_RECORD_ID,
    W.CONSTITUENT_ID,
    IFF(RA.LEGACY_INTENDER_ID IS NULL, 'POST', 'PATCH') AS ACTION,
    RA.LEGACY_INTENDER_ID::VARCHAR AS CUSTOM_FIELD_ID,
    CASE
        WHEN RA.LEGACY_INTENDER_ID IS NULL
            THEN OBJECT_CONSTRUCT(
                'parent_id', W.CONSTITUENT_ID,
                'category', 'Legacy Intender',
                'value', NULLIF(TRIM(W.LEGACY_INTENDER), '')
            )
        ELSE OBJECT_CONSTRUCT('value', NULLIF(TRIM(W.LEGACY_INTENDER), ''))
    END AS PAYLOAD
FROM WINNER AS W
LEFT JOIN RE_ATTRS AS RA ON W.CONSTITUENT_ID = RA.CONSTITUENT_ID
LEFT JOIN RE_ATTRS_EXISTS AS RE_EXISTS
    ON
        W.CONSTITUENT_ID = RE_EXISTS.CONSTITUENT_ID
        AND RE_EXISTS.ATTRIBUTENAME = 'Legacy Intender'
        AND RE_EXISTS.ATTR_VALUE = NULLIF(TRIM(W.LEGACY_INTENDER), '')
WHERE
    NULLIF(TRIM(W.LEGACY_INTENDER), '') IS NOT NULL
    AND (
        RA.LEGACY_INTENDER_ID IS NULL          -- POST: no row exists
        -- PATCH: winner absent from all rows
        OR RE_EXISTS.CONSTITUENT_ID IS NULL
    )

UNION ALL

-- Legacy Pledger (Text)
-- Existence gate: suppress when winner (exact) already held on any RE row.
SELECT
    W.GOLDEN_RECORD_ID,
    W.CONSTITUENT_ID,
    IFF(RA.LEGACY_PLEDGER_ID IS NULL, 'POST', 'PATCH') AS ACTION,
    RA.LEGACY_PLEDGER_ID::VARCHAR AS CUSTOM_FIELD_ID,
    CASE
        WHEN RA.LEGACY_PLEDGER_ID IS NULL
            THEN OBJECT_CONSTRUCT(
                'parent_id', W.CONSTITUENT_ID,
                'category', 'Legacy Pledger',
                'value', NULLIF(TRIM(W.LEGACY_PLEDGER), '')
            )
        ELSE OBJECT_CONSTRUCT('value', NULLIF(TRIM(W.LEGACY_PLEDGER), ''))
    END AS PAYLOAD
FROM WINNER AS W
LEFT JOIN RE_ATTRS AS RA ON W.CONSTITUENT_ID = RA.CONSTITUENT_ID
LEFT JOIN RE_ATTRS_EXISTS AS RE_EXISTS
    ON
        W.CONSTITUENT_ID = RE_EXISTS.CONSTITUENT_ID
        AND RE_EXISTS.ATTRIBUTENAME = 'Legacy Pledger'
        AND RE_EXISTS.ATTR_VALUE = NULLIF(TRIM(W.LEGACY_PLEDGER), '')
WHERE
    NULLIF(TRIM(W.LEGACY_PLEDGER), '') IS NOT NULL
    AND (
        RA.LEGACY_PLEDGER_ID IS NULL           -- POST: no row exists
        -- PATCH: winner absent from all rows
        OR RE_EXISTS.CONSTITUENT_ID IS NULL
    )

UNION ALL

-- Legacy Considerer (Text)
-- Existence gate: suppress when winner (exact) already held on any RE row.
SELECT
    W.GOLDEN_RECORD_ID,
    W.CONSTITUENT_ID,
    IFF(RA.LEGACY_CONSIDERER_ID IS NULL, 'POST', 'PATCH') AS ACTION,
    RA.LEGACY_CONSIDERER_ID::VARCHAR AS CUSTOM_FIELD_ID,
    CASE
        WHEN RA.LEGACY_CONSIDERER_ID IS NULL
            THEN OBJECT_CONSTRUCT(
                'parent_id', W.CONSTITUENT_ID,
                'category', 'Legacy Considerer',
                'value', NULLIF(TRIM(W.LEGACY_CONSIDERER), '')
            )
        ELSE OBJECT_CONSTRUCT('value', NULLIF(TRIM(W.LEGACY_CONSIDERER), ''))
    END AS PAYLOAD
FROM WINNER AS W
LEFT JOIN RE_ATTRS AS RA ON W.CONSTITUENT_ID = RA.CONSTITUENT_ID
LEFT JOIN RE_ATTRS_EXISTS AS RE_EXISTS
    ON
        W.CONSTITUENT_ID = RE_EXISTS.CONSTITUENT_ID
        AND RE_EXISTS.ATTRIBUTENAME = 'Legacy Considerer'
        AND RE_EXISTS.ATTR_VALUE = NULLIF(TRIM(W.LEGACY_CONSIDERER), '')
WHERE
    NULLIF(TRIM(W.LEGACY_CONSIDERER), '') IS NOT NULL
    AND (
        RA.LEGACY_CONSIDERER_ID IS NULL        -- POST: no row exists
        -- PATCH: winner absent from all rows
        OR RE_EXISTS.CONSTITUENT_ID IS NULL
    )

UNION ALL

-- Legacy Enquirer (Text)
-- Existence gate: suppress when winner (exact) already held on any RE row.
SELECT
    W.GOLDEN_RECORD_ID,
    W.CONSTITUENT_ID,
    IFF(RA.LEGACY_ENQUIRER_ID IS NULL, 'POST', 'PATCH') AS ACTION,
    RA.LEGACY_ENQUIRER_ID::VARCHAR AS CUSTOM_FIELD_ID,
    CASE
        WHEN RA.LEGACY_ENQUIRER_ID IS NULL
            THEN OBJECT_CONSTRUCT(
                'parent_id', W.CONSTITUENT_ID,
                'category', 'Legacy Enquirer',
                'value', NULLIF(TRIM(W.LEGACY_ENQUIRER), '')
            )
        ELSE OBJECT_CONSTRUCT('value', NULLIF(TRIM(W.LEGACY_ENQUIRER), ''))
    END AS PAYLOAD
FROM WINNER AS W
LEFT JOIN RE_ATTRS AS RA ON W.CONSTITUENT_ID = RA.CONSTITUENT_ID
LEFT JOIN RE_ATTRS_EXISTS AS RE_EXISTS
    ON
        W.CONSTITUENT_ID = RE_EXISTS.CONSTITUENT_ID
        AND RE_EXISTS.ATTRIBUTENAME = 'Legacy Enquirer'
        AND RE_EXISTS.ATTR_VALUE = NULLIF(TRIM(W.LEGACY_ENQUIRER), '')
WHERE
    NULLIF(TRIM(W.LEGACY_ENQUIRER), '') IS NOT NULL
    AND (
        RA.LEGACY_ENQUIRER_ID IS NULL          -- POST: no row exists
        -- PATCH: winner absent from all rows
        OR RE_EXISTS.CONSTITUENT_ID IS NULL
    );