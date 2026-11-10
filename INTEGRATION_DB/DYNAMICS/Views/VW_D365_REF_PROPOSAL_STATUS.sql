create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_PROPOSAL_STATUS(
	RE_STATUS,
	D365_OUTCOME_LABEL,
	D365_OUTCOME_VALUE,
	D365_EVENTPACKAGE_STATUS_LABEL,
	D365_EVENTPACKAGE_STATUSCODE,
	MAP_STATUS,
	NOTE
) as
-- RE proposal status to two D365 values: the opportunity outcome and the event
-- package status reason. A proposal loads to one table only (see
-- VW_D365_REF_COMMUNITY_APPEAL). RE values come from the live proposals, the
-- option values from the D365 metadata. An empty outcome means open or
-- undecided, not unsuccessful. Completed and Transferred stay empty until NAS
-- says otherwise. The event package status is a draft: only the clear same-
-- name statuses are filled, and NAS supplies the rest. MAP_STATUS: MAPPED (an
-- outcome or a status), UNMAPPED (decided: neither), NEW.
WITH RE_VALUES AS (
    SELECT DISTINCT TRIM(STATUSDESCRIPTION) AS RE_STATUS
    FROM RAW.RAISERS_EDGE.VW_ODS_T_PROPOSALS
    WHERE NULLIF(TRIM(STATUSDESCRIPTION), '') IS NOT NULL
),

DECISIONS AS (
    SELECT
        COLUMN1 AS RE_STATUS,
        COLUMN2 AS D365_OUTCOME_LABEL,
        COLUMN3 AS D365_EVENTPACKAGE_STATUS_LABEL,
        COLUMN4 AS NOTE
    FROM
        VALUES
        (
            'Successful',
            'Successful',
            'Successful',
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'AFA Awarded',
            'Successful',
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Received',
            'Successful',
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Pledged',
            'Successful',
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Rejected',
            'Unsuccessful',
            'Rejected',
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Withdrawn',
            'Unsuccessful',
            'Withdrawn',
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'No Response',
            'Unsuccessful',
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'No Contact Made',
            'Unsuccessful',
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'AFA Not Awarded',
            'Unsuccessful',
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Active',
            NULL,
            'Active',
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Completed',
            NULL,
            'Completed',
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Transferred',
            NULL,
            'Transferred',
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Pending',
            NULL,
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Submitted',
            NULL,
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Planned',
            NULL,
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Interested',
            NULL,
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        ),
        (
            'Shortlisted',
            NULL,
            NULL,
            'Outcome is empty while the proposal is open or undecided'
        )
)

SELECT
    R.RE_STATUS,
    D.D365_OUTCOME_LABEL,
    OUTCOME.OPTION_VALUE AS D365_OUTCOME_VALUE,
    D.D365_EVENTPACKAGE_STATUS_LABEL,
    EP.OPTION_VALUE AS D365_EVENTPACKAGE_STATUSCODE,
    CASE
        WHEN D.RE_STATUS IS NULL THEN 'NEW'
        WHEN
            D.D365_OUTCOME_LABEL IS NULL
            AND D.D365_EVENTPACKAGE_STATUS_LABEL IS NULL
            THEN 'UNMAPPED'
        WHEN
            (D.D365_OUTCOME_LABEL IS NOT NULL AND OUTCOME.OPTION_VALUE IS NULL)
            OR (
                D.D365_EVENTPACKAGE_STATUS_LABEL IS NOT NULL
                AND EP.OPTION_VALUE IS NULL
            )
            THEN 'NO_D365_OPTION'
        ELSE 'MAPPED'
    END AS MAP_STATUS,
    D.NOTE
FROM RE_VALUES AS R
LEFT JOIN DECISIONS AS D ON R.RE_STATUS = D.RE_STATUS
LEFT JOIN RAW.DYNAMICS.VW_ODS_METADATA_OPTIONS AS OUTCOME
    ON
        OUTCOME.ENTITY_LOGICALNAME = 'opportunity'
        AND OUTCOME.ATTRIBUTE_LOGICALNAME = 'mhnas_outcome'
        AND UPPER(TRIM(D.D365_OUTCOME_LABEL))
        = UPPER(TRIM(OUTCOME.OPTION_LABEL))
LEFT JOIN RAW.DYNAMICS.VW_ODS_METADATA_OPTIONS AS EP
    ON
        EP.ENTITY_LOGICALNAME = 'msnfp_eventpackage'
        AND EP.ATTRIBUTE_LOGICALNAME = 'statuscode'
        AND UPPER(TRIM(D.D365_EVENTPACKAGE_STATUS_LABEL)) = UPPER(TRIM(EP.OPTION_LABEL));