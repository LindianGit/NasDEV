create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_EVENT(
	RE_EVENT_ID,
	RE_EVENT_REF,
	RE_CAMPAIGN_ID,
	RE_EVENT_TYPE,
	D365_ID,
	CAMPAIGN_D365_ID,
	MHA_EVENTTYPE_D365_ID,
	LOAD_ACTION,
	HOLD_REASON,
	PAYLOAD,
	MHA_EVENTCODE,
	MHA_EVENTTYPEID,
	MHA_LOCATIONTYPE,
	MHA_TARGETPARTICIPANTS,
	MHNAS_UNIQUEID,
	MSNFP_CAMPAIGNID,
	MSNFP_CAPACITY,
	MSNFP_DESCRIPTION,
	MSNFP_GOAL,
	MSNFP_NAME,
	MSNFP_PROPOSEDEND,
	MSNFP_PROPOSEDSTART,
	OVERRIDDENCREATEDON,
	OWNINGTEAM
) as
-- One D365 event per RE event. The key is the RE event reference, which D365
-- holds in mha_eventcode (matched ignoring case and padding). The reference is
-- unique in RE and the event name is not, so mhnas_uniqueid carries the
-- reference too. An event already in D365 is EXISTS and keeps its D365 id.
-- Where D365 holds two rows of one reference, the oldest wins.
-- Campaign: the D365 campaign id comes from VW_D365_CAMPAIGN, so a campaign
-- D365 already held binds the same way as a new one.
-- Event type: the client owns the event type list, so the RE type description
-- is matched by name to the D365 event types, ignoring case and padding.
-- An event whose campaign or type has no D365 id yet is held with
-- PARENT_MISSING and the missing parents. An event with neither loads without
-- them.
-- Location: an RE location that says virtual or online is Virtual. Any other
-- location is In-person / Hybrid. No location sends nothing.
-- Dates: the D365 start and end are date only, so the RE start and end times
-- are not sent. The RE date added is the created date, sent as a date.
WITH D365_EVENTS AS (
    SELECT
        UPPER(TRIM(MHA_EVENTCODE)) AS CODE_KEY,
        MSNFP_EVENTID
    FROM RAW.DYNAMICS.VW_ODS_MSNFP_EVENTS
    WHERE NULLIF(TRIM(MHA_EVENTCODE), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(MHA_EVENTCODE))
            ORDER BY CREATEDON, MSNFP_EVENTID
        ) = 1
),

D365_EVENT_TYPES AS (
    SELECT
        UPPER(TRIM(MHA_NAME)) AS NAME_KEY,
        MHA_EVENTTYPEID
    FROM RAW.DYNAMICS.VW_ODS_MHA_EVENTTYPES
    WHERE NULLIF(TRIM(MHA_NAME), '') IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY UPPER(TRIM(MHA_NAME))
            ORDER BY CREATEDON, MHA_EVENTTYPEID
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
        D365_TABLE = 'msnfp_event'
        AND IS_OPEN
        AND ROW_CONDITION_KEY IS NULL
),

MAPPED AS (
    SELECT
        E.ID AS RE_EVENT_ID,
        E.EVENTREF AS RE_EVENT_REF,
        E.CAMPAIGNCODE AS RE_CAMPAIGN_ID,
        NULLIF(TRIM(E.TYPEDESCRIPTION), '') AS RE_EVENT_TYPE,
        D.MSNFP_EVENTID AS D365_ID,
        C.D365_ID AS CAMPAIGN_D365_ID,
        T.MHA_EVENTTYPEID AS MHA_EVENTTYPE_D365_ID,
        G.GATE_CODES,
        -- Parents with an RE value but no D365 id, in a fixed order
        NULLIF(
            ARRAY_TO_STRING(
                ARRAY_CONSTRUCT_COMPACT(
                    IFF(
                        E.CAMPAIGNCODE IS NOT NULL AND C.D365_ID IS NULL,
                        'campaign',
                        NULL
                    ),
                    IFF(
                        NULLIF(TRIM(E.TYPEDESCRIPTION), '') IS NOT NULL
                        AND T.MHA_EVENTTYPEID IS NULL,
                        'mha_eventtype',
                        NULL
                    )
                ),
                ','
            ),
            ''
        ) AS MISSING_PARENTS,
        NULLIF(TRIM(E.EVENTREF), '') AS MHA_EVENTCODE,
        T.MHA_EVENTTYPEID,
        CASE
            WHEN NULLIF(TRIM(E.LOCATION), '') IS NULL THEN NULL
            WHEN
                UPPER(E.LOCATION) LIKE '%VIRTUAL%'
                OR UPPER(E.LOCATION) LIKE '%ONLINE%'
                THEN 862940001
            ELSE 862940000
        END AS MHA_LOCATIONTYPE,
        E.NUMBERINVITED AS MHA_TARGETPARTICIPANTS,
        NULLIF(TRIM(E.EVENTREF), '') AS MHNAS_UNIQUEID,
        C.D365_ID AS MSNFP_CAMPAIGNID,
        E.CAPACITY AS MSNFP_CAPACITY,
        NULLIF(TRIM(E.DESCRIPTION), '') AS MSNFP_DESCRIPTION,
        ROUND(E.GOAL, 2)::NUMBER(18, 2) AS MSNFP_GOAL,
        NULLIF(TRIM(E.NAME), '') AS MSNFP_NAME,
        TRY_TO_DATE(LEFT(E.ENDDATE, 10)) AS MSNFP_PROPOSEDEND,
        TRY_TO_DATE(LEFT(E.STARTDATE, 10)) AS MSNFP_PROPOSEDSTART,
        TRY_TO_TIMESTAMP_NTZ(E.DATEADDED)::DATE AS OVERRIDDENCREATEDON,
        -- Placeholder: no D365 team exists per RE event group yet, and
        -- ownership is set through ownerid, so this is never filled and never
        -- sent
        NULL::VARCHAR AS OWNINGTEAM
    FROM RAW.RAISERS_EDGE.VW_ODS_T_EVENTS AS E
    LEFT JOIN INTEGRATION_DB.DYNAMICS.VW_D365_CAMPAIGN AS C
        ON E.CAMPAIGNCODE = C.RE_CAMPAIGN_ID
    LEFT JOIN D365_EVENT_TYPES AS T
        ON UPPER(TRIM(E.TYPEDESCRIPTION)) = T.NAME_KEY
    LEFT JOIN D365_EVENTS AS D
        ON UPPER(TRIM(E.EVENTREF)) = D.CODE_KEY
    CROSS JOIN GATES AS G
)

SELECT
    RE_EVENT_ID,
    RE_EVENT_REF,
    RE_CAMPAIGN_ID,
    RE_EVENT_TYPE,
    D365_ID,
    CAMPAIGN_D365_ID,
    MHA_EVENTTYPE_D365_ID,
    CASE
        WHEN D365_ID IS NOT NULL THEN 'EXISTS'
        WHEN GATE_CODES IS NOT NULL THEN 'HOLD'
        WHEN MISSING_PARENTS IS NOT NULL THEN 'HOLD'
        ELSE 'CREATE'
    END AS LOAD_ACTION,
    CASE
        WHEN D365_ID IS NOT NULL THEN NULL
        WHEN GATE_CODES IS NOT NULL THEN 'GATE:' || GATE_CODES
        WHEN
            MISSING_PARENTS IS NOT NULL
            THEN 'PARENT_MISSING:' || MISSING_PARENTS
    END AS HOLD_REASON,
    -- owningteam is a placeholder and stays out of the body
    OBJECT_CONSTRUCT(
        'mha_eventcode', MHA_EVENTCODE,
        -- lookup: navigation property with @odata.bind, never the plain key
        'mha_EventTypeId@odata.bind', IFF(
            MHA_EVENTTYPEID IS NOT NULL,
            '/mha_eventtypes(' || MHA_EVENTTYPEID || ')',
            NULL
        ),
        'mha_locationtype', MHA_LOCATIONTYPE,
        'mha_targetparticipants', MHA_TARGETPARTICIPANTS,
        'mhnas_uniqueid', MHNAS_UNIQUEID,
        -- lookup: navigation property with @odata.bind, never the plain key
        'msnfp_CampaignId@odata.bind', IFF(
            MSNFP_CAMPAIGNID IS NOT NULL,
            '/campaigns(' || MSNFP_CAMPAIGNID || ')',
            NULL
        ),
        'msnfp_capacity', MSNFP_CAPACITY,
        'msnfp_description', MSNFP_DESCRIPTION,
        'msnfp_goal', MSNFP_GOAL,
        'msnfp_name', MSNFP_NAME,
        'msnfp_proposedend', TO_CHAR(MSNFP_PROPOSEDEND, 'YYYY-MM-DD'),
        'msnfp_proposedstart', TO_CHAR(MSNFP_PROPOSEDSTART, 'YYYY-MM-DD'),
        'overriddencreatedon', TO_CHAR(OVERRIDDENCREATEDON, 'YYYY-MM-DD')
    ) AS PAYLOAD,
    MHA_EVENTCODE,
    MHA_EVENTTYPEID,
    MHA_LOCATIONTYPE,
    MHA_TARGETPARTICIPANTS,
    MHNAS_UNIQUEID,
    MSNFP_CAMPAIGNID,
    MSNFP_CAPACITY,
    MSNFP_DESCRIPTION,
    MSNFP_GOAL,
    MSNFP_NAME,
    MSNFP_PROPOSEDEND,
    MSNFP_PROPOSEDSTART,
    OVERRIDDENCREATEDON,
    OWNINGTEAM
FROM MAPPED;