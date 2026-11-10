create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_PLEDGE_STATUS(
	RE_STATUS,
	D365_STATUS_LABEL,
	D365_STATUSCODE,
	MAP_STATUS,
	NOTE
) as
-- RE pledge status to the D365 donor commitment status reason. RE values come
-- from the live pledges, the option value from the D365 metadata by label. The
-- state for each status comes from the metadata, never from this view.
-- MAP_STATUS: MAPPED, UNMAPPED (decided: no target), NEW (an RE value with no
-- decision), NO_D365_OPTION (the label is not in the metadata).
WITH RE_VALUES AS (
    SELECT DISTINCT TRIM(STATUS) AS RE_STATUS
    FROM RAW.RAISERS_EDGE.VW_ODS_T_PLEDGES
    WHERE NULLIF(TRIM(STATUS), '') IS NOT NULL
),

DECISIONS AS (
    SELECT
        COLUMN1 AS RE_STATUS,
        COLUMN2 AS D365_STATUS_LABEL,
        COLUMN3 AS NOTE
    FROM
        VALUES
        ('Active', 'In Progress', 'Proposed'),
        ('Completed', 'Completed', 'Proposed'),
        ('Cancelled', 'Cancelled', 'Proposed'),
        (
            'Terminated',
            'Cancelled',
            'Not Write Off: write-offs are their own gift type'
        )
)

SELECT
    R.RE_STATUS,
    D.D365_STATUS_LABEL,
    O.OPTION_VALUE AS D365_STATUSCODE,
    CASE
        WHEN D.RE_STATUS IS NULL THEN 'NEW'
        WHEN D.D365_STATUS_LABEL IS NULL THEN 'UNMAPPED'
        WHEN O.OPTION_VALUE IS NULL THEN 'NO_D365_OPTION'
        ELSE 'MAPPED'
    END AS MAP_STATUS,
    D.NOTE
FROM RE_VALUES AS R
LEFT JOIN DECISIONS AS D ON R.RE_STATUS = D.RE_STATUS
LEFT JOIN RAW.DYNAMICS.VW_ODS_METADATA_OPTIONS AS O
    ON
        O.ENTITY_LOGICALNAME = 'msnfp_donorcommitment'
        AND O.ATTRIBUTE_LOGICALNAME = 'statuscode'
        AND UPPER(TRIM(D.D365_STATUS_LABEL)) = UPPER(TRIM(O.OPTION_LABEL));