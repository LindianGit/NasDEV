create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_PARTICIPANT_STATUS(
	RE_SOURCE_COLUMN,
	RE_VALUE,
	D365_STATUS_LABEL,
	D365_STATUSCODE,
	MAP_STATUS,
	NOTE
) as
-- RE event participant values to the D365 event package status reason. Use the
-- STATUS rows first. Where the status gives no target, use the PARTICIPATION
-- rows for the outcomes they carry. Anything still unmapped stays empty.
-- STATUS values come from the live participants, so a new one shows as NEW.
-- Most PARTICIPATION values describe the kind of participant, not a status, so
-- only the decided ones are listed. MAP_STATUS: MAPPED, UNMAPPED (decided: no
-- target), NEW (an RE value with no decision), NO_D365_OPTION (the label is
-- not in the metadata).
WITH RE_STATUS AS (
    SELECT DISTINCT
        'STATUS' AS RE_SOURCE_COLUMN,
        TRIM(STATUSDESCRIPTION) AS RE_VALUE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_EVENTPARTICIPANTS
    WHERE NULLIF(TRIM(STATUSDESCRIPTION), '') IS NOT NULL
),

RE_PARTICIPATION AS (
    SELECT DISTINCT
        'PARTICIPATION' AS RE_SOURCE_COLUMN,
        TRIM(PARTICIPATIONDESCRIPTION) AS RE_VALUE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_EVENTPARTICIPANTS
    WHERE NULLIF(TRIM(PARTICIPATIONDESCRIPTION), '') IS NOT NULL
),

DECISIONS AS (
    SELECT
        COLUMN1 AS RE_SOURCE_COLUMN,
        COLUMN2 AS RE_VALUE,
        COLUMN3 AS D365_STATUS_LABEL,
        COLUMN4 AS NOTE
    FROM
        VALUES
        ('STATUS', 'Invited', 'Invited', 'Clear match'),
        ('STATUS', 'Registered', 'Registered', 'Clear match'),
        ('STATUS', 'Accepted', 'Accepted', 'Clear match'),
        ('STATUS', 'Attended', 'Completed', 'Clear match'),
        ('STATUS', 'Completed', 'Completed', 'Clear match'),
        ('STATUS', 'Not Attending', 'Not Attending', 'Clear match'),
        ('STATUS', 'Rejected', 'Rejected', 'Clear match'),
        ('STATUS', 'Did Not Respond', 'Did not respond', 'Clear match'),
        ('STATUS', 'Dropped out', 'Drop Out', 'Clear match'),
        ('STATUS', 'Dropout GB', 'Drop Out', 'Clear match'),
        ('STATUS', 'Dropout OP', 'Drop Out', 'Clear match'),
        ('STATUS', 'Duplicate', 'Duplicate', 'Clear match'),
        ('STATUS', 'Transferred', 'Transferred', 'Clear match'),
        ('STATUS', 'Enquired', 'Enquiry', 'Clear match'),
        (
            'STATUS',
            'OP',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'GB',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Pack Sent',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Contacted',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Thanked',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Pending',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Planned',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Booking form-after event full',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Responded',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Multiple Event',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'Communicated',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'STATUS',
            'OP&GB',
            NULL,
            'Not a status: NAS events team must supply the target'
        ),
        (
            'PARTICIPATION',
            'Event Enquiry',
            'Enquiry',
            'Used only when the status gives no target'
        ),
        (
            'PARTICIPATION',
            'Event Rejection',
            'Rejected',
            'Used only when the status gives no target'
        ),
        (
            'PARTICIPATION',
            'Event Dropout',
            'Drop Out',
            'Used only when the status gives no target'
        ),
        (
            'PARTICIPATION',
            'Event Deferral',
            'Deferred',
            'Used only when the status gives no target'
        ),
        -- ASSUMED: no waiting list status found in the D365 metadata; left unmapped
        (
            'PARTICIPATION',
            'Event Waiting List',
            NULL,
            'D365 has no waiting list status'
        )
),

RE_VALUES AS (
    SELECT * FROM RE_STATUS
    UNION ALL
    -- Only the decided participation values are listed.
    SELECT P.*
    FROM RE_PARTICIPATION AS P
    INNER JOIN DECISIONS AS D
        ON P.RE_SOURCE_COLUMN = D.RE_SOURCE_COLUMN AND P.RE_VALUE = D.RE_VALUE
)

SELECT
    R.RE_SOURCE_COLUMN,
    R.RE_VALUE,
    D.D365_STATUS_LABEL,
    O.OPTION_VALUE AS D365_STATUSCODE,
    CASE
        WHEN D.RE_VALUE IS NULL THEN 'NEW'
        WHEN D.D365_STATUS_LABEL IS NULL THEN 'UNMAPPED'
        WHEN O.OPTION_VALUE IS NULL THEN 'NO_D365_OPTION'
        ELSE 'MAPPED'
    END AS MAP_STATUS,
    D.NOTE
FROM RE_VALUES AS R
LEFT JOIN DECISIONS AS D
    ON R.RE_SOURCE_COLUMN = D.RE_SOURCE_COLUMN AND R.RE_VALUE = D.RE_VALUE
LEFT JOIN RAW.DYNAMICS.VW_ODS_METADATA_OPTIONS AS O
    ON
        O.ENTITY_LOGICALNAME = 'msnfp_eventpackage'
        AND O.ATTRIBUTE_LOGICALNAME = 'statuscode'
        AND UPPER(TRIM(D.D365_STATUS_LABEL)) = UPPER(TRIM(O.OPTION_LABEL));