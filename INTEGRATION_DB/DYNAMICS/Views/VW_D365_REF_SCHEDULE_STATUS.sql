create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_SCHEDULE_STATUS(
	RE_STATUS,
	D365_STATUS_LABEL,
	D365_STATUSCODE,
	MAP_STATUS,
	NOTE
) as
-- RE regular giving status to the D365 payment schedule status reason. RE
-- values come from the live schedules, the option value from the D365
-- metadata. D365 has two Cancelled options, so the decision also names the
-- state (0 active, 1 inactive). A cancelled or held schedule must never load
-- as live. MAP_STATUS: MAPPED, UNMAPPED (decided: no target), NEW (an RE value
-- with no decision), NO_D365_OPTION (the label is not in the metadata).
WITH RE_VALUES AS (
    SELECT DISTINCT TRIM(STATUS) AS RE_STATUS
    FROM RAW.RAISERS_EDGE.VW_ODS_T_REGULARGIVING
    WHERE NULLIF(TRIM(STATUS), '') IS NOT NULL
),

DECISIONS AS (
    SELECT
        COLUMN1 AS RE_STATUS,
        COLUMN2 AS D365_STATUS_LABEL,
        COLUMN3 AS NOTE,
        COLUMN4 AS D365_STATE_CODE
    FROM
        VALUES
        ('Active', 'Active', 'Live schedule', 0),
        (
            'Cancelled',
            'Cancelled',
            'Inactive state: must never load as live',
            1
        ),
        -- ASSUMED: mapped to the inactive Cancelled status; no Terminated status exists
        ('Terminated', 'Cancelled', 'No Terminated status in D365', 1),
        -- ASSUMED: mapped to Inactive; no Completed status exists
        ('Completed', 'Inactive', 'No Completed status in D365', 1),
        -- ASSUMED: no hold status found in the D365 metadata; left unmapped
        ('Held', NULL, 'D365 has no hold status: NAS must choose', NULL)
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
        O.ENTITY_LOGICALNAME = 'msnfp_paymentschedule'
        AND O.ATTRIBUTE_LOGICALNAME = 'statuscode'
        AND UPPER(TRIM(D.D365_STATUS_LABEL)) = UPPER(TRIM(O.OPTION_LABEL))
        AND D.D365_STATE_CODE = O.STATE;