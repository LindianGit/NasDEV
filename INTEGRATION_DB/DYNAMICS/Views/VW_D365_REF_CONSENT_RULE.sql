create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_CONSENT_RULE(
	RE_ATTRIBUTE_NAME,
	RE_VALUE,
	CHANNEL,
	CONSENT_TYPE,
	D365_CONSENT_TYPE_ID,
	CONSENT_VALUE,
	MAP_STATUS,
	NOTE
) as
-- Turns an RE preference or exclusion value into a D365 consent: channel,
-- consent type and value. RE values come from the live attributes. The consent
-- type is matched by name to the D365 consent types. CHANNEL is POST, EMAIL,
-- SMS, TELEPHONE or ALL. CONSENT_VALUE is IN or OUT. A channel with no row for
-- a type is No Response. When in doubt the rule is Out or No Response, never
-- In. Where one party has several values for a type and channel, the most
-- recent wins (applied by the consumer). MAP_STATUS: MAPPED, UNMAPPED
-- (decided: not a consent), NEW (an RE value no rule covers), TYPE_MISSING
-- (the rule is clear but D365 has no consent type of that name).
WITH RE_VALUES AS (
    SELECT DISTINCT
        ATTRIBUTENAME AS RE_ATTRIBUTE_NAME,
        TRIM(ATTRIBUTEVALUE) AS RE_VALUE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES
    WHERE ATTRIBUTENAME IN (
        'Postal Preferences', 'Telephone Preferences', 'Email Preferences',
        'SMS Preferences', 'Contact Exclusions'
    )
    AND NULLIF(TRIM(ATTRIBUTEVALUE), '') IS NOT NULL
),

CHANNELS AS (
    SELECT
        COLUMN1 AS RE_ATTRIBUTE_NAME,
        COLUMN2 AS CHANNEL,
        COLUMN3 AS CHANNEL_LABEL
    FROM
        VALUES
        ('Postal Preferences', 'POST', 'Post'),
        ('Telephone Preferences', 'TELEPHONE', 'Telephone'),
        ('Email Preferences', 'EMAIL', 'Email'),
        ('SMS Preferences', 'SMS', 'SMS')
),

EXCEPTIONS AS (
    SELECT
        COLUMN1 AS RE_ATTRIBUTE_NAME,
        COLUMN2 AS RE_VALUE,
        COLUMN3 AS CHANNEL,
        COLUMN4 AS CONSENT_TYPE,
        COLUMN5 AS CONSENT_VALUE,
        COLUMN6 AS NOTE
    FROM VALUES
    -- ASSUMED: in doubt the rule is No Response, never In; left unmapped
    (
        'Postal Preferences',
        'Assumed Opt In All Post',
        NULL,
        NULL,
        NULL,
        'Assumed opt in is not a recorded opt in'
    ),
    -- ASSUMED: marker value, not a consent; left unmapped (D365 has a Seed type, NAS decides)
    ('Postal Preferences', 'Seed', NULL, NULL, NULL, 'Seed record'),
    -- ASSUMED: marker value, not a consent; left unmapped (D365 has a Seed type, NAS decides)
    ('Postal Preferences', 'YAM Seed', NULL, NULL, NULL, 'Seed record'),
    -- ASSUMED: marker value, not a consent; left unmapped
    (
        'Postal Preferences',
        'Z DELETE DST USE ONLY',
        NULL,
        NULL,
        NULL,
        'Deletion marker'
    ),
    -- ASSUMED: in doubt the rule is No Response, never In; left unmapped
    (
        'Telephone Preferences',
        'Assumed Opt In All Telephone',
        NULL,
        NULL,
        NULL,
        'Assumed opt in is not a recorded opt in'
    ),
    -- ASSUMED: marker value, not a consent; left unmapped (D365 has a Seed type, NAS decides)
    ('Telephone Preferences', 'Seed', NULL, NULL, NULL, 'Seed record'),
    -- ASSUMED: marker value, not a consent; left unmapped (D365 has a Seed type, NAS decides)
    ('Telephone Preferences', 'YAM Seed', NULL, NULL, NULL, 'Seed record'),
    -- ASSUMED: marker value, not a consent; left unmapped
    (
        'Telephone Preferences',
        'Z DELETE DST USE ONLY',
        NULL,
        NULL,
        NULL,
        'Deletion marker'
    ),
    -- ASSUMED: in doubt the rule is No Response, never In; left unmapped
    (
        'Email Preferences',
        'Assumed Opt In All Email',
        NULL,
        NULL,
        NULL,
        'Assumed opt in is not a recorded opt in'
    ),
    -- ASSUMED: marker value, not a consent; left unmapped (D365 has a Seed type, NAS decides)
    ('Email Preferences', 'Seed', NULL, NULL, NULL, 'Seed record'),
    -- ASSUMED: marker value, not a consent; left unmapped (D365 has a Seed type, NAS decides)
    ('Email Preferences', 'YAM Seed', NULL, NULL, NULL, 'Seed record'),
    -- ASSUMED: marker value, not a consent; left unmapped
    (
        'Email Preferences',
        'Z DELETE DST USE ONLY',
        NULL,
        NULL,
        NULL,
        'Deletion marker'
    ),
    -- ASSUMED: in doubt the rule is No Response, never In; left unmapped
    (
        'SMS Preferences',
        'Assumed Opt In All SMS',
        NULL,
        NULL,
        NULL,
        'Assumed opt in is not a recorded opt in'
    ),
    -- ASSUMED: marker value, not a consent; left unmapped (D365 has a Seed type, NAS decides)
    ('SMS Preferences', 'Seed', NULL, NULL, NULL, 'Seed record'),
    -- ASSUMED: marker value, not a consent; left unmapped (D365 has a Seed type, NAS decides)
    ('SMS Preferences', 'YAM Seed', NULL, NULL, NULL, 'Seed record'),
    -- ASSUMED: marker value, not a consent; left unmapped
    (
        'SMS Preferences',
        'Z DELETE DST USE ONLY',
        NULL,
        NULL,
        NULL,
        'Deletion marker'
    ),
    -- ASSUMED: marker value, not a consent; left unmapped
    (
        'Postal Preferences',
        'z Anonymous',
        NULL,
        NULL,
        NULL,
        'Anonymised marker'
    ),
    (
        'Contact Exclusions',
        'No Lottery',
        'ALL',
        'Lottery',
        'OUT',
        'All channels: an opt out must not be narrower than intended'
    ),
    (
        'Contact Exclusions',
        'No Raffle Tickets',
        'ALL',
        'Raffle Tickets',
        'OUT',
        'All channels: an opt out must not be narrower than intended'
    ),
    -- ASSUMED: general type taken as 'Marketing All Channels': no other general type in D365
    (
        'Contact Exclusions',
        'Opt Out All Contact',
        'ALL',
        'Marketing All Channels',
        'OUT',
        'Opt out of every channel'
    ),
    (
        'Contact Exclusions',
        'Missing Data',
        NULL,
        NULL,
        NULL,
        'Exclusion record only: not a consent'
    ),
    (
        'Contact Exclusions',
        'Under 16',
        NULL,
        NULL,
        NULL,
        'Exclusion record only: not a consent'
    ),
    (
        'Contact Exclusions',
        '16 or 17 age',
        NULL,
        NULL,
        NULL,
        'Exclusion record only: not a consent'
    ),
    (
        'Contact Exclusions',
        'No External Data Appending or Profiling',
        NULL,
        NULL,
        NULL,
        'Exclusion record only: not a consent'
    ),
    (
        'Contact Exclusions',
        'No Surveys',
        NULL,
        NULL,
        NULL,
        'Exclusion record only: not a consent'
    ),
    (
        'Contact Exclusions',
        'Permanent Opt Out - Vulnerability Policy',
        NULL,
        NULL,
        NULL,
        'Exclusion record only: not a consent'
    ),
    (
        'Contact Exclusions',
        'Temporary Opt Out - Vulnerability Policy',
        NULL,
        NULL,
        NULL,
        'Exclusion record only: not a consent'
    )
),

RULES AS (
    SELECT
        R.RE_ATTRIBUTE_NAME,
        R.RE_VALUE,
        E.RE_VALUE IS NOT NULL AS IS_EXCEPTION,
        COALESCE(E.CHANNEL, C.CHANNEL) AS CHANNEL,
        CASE
            WHEN E.RE_VALUE IS NOT NULL THEN E.CONSENT_TYPE
            WHEN C.CHANNEL IS NULL THEN NULL
            WHEN
                STARTSWITH(R.RE_VALUE, 'Opt ')
                AND ENDSWITH(R.RE_VALUE, ' ' || C.CHANNEL_LABEL)
                -- ASSUMED: the general type is 'Marketing All Channels', the only general type in D365
                THEN 'Marketing All Channels'
            WHEN
                STARTSWITH(R.RE_VALUE, 'FPS - No ')
                AND ENDSWITH(R.RE_VALUE, ' ' || C.CHANNEL_LABEL)
                -- ASSUMED: preference service opt outs map to the D365 type 'FPS All Channels'
                THEN 'FPS All Channels'
            -- ASSUMED: a retired 'z No <type>' value is read as an opt out against <type>
            WHEN STARTSWITH(R.RE_VALUE, 'z No ') THEN SUBSTR(R.RE_VALUE, 6)
            WHEN STARTSWITH(R.RE_VALUE, 'No ') THEN SUBSTR(R.RE_VALUE, 4)
        END AS CONSENT_TYPE,
        CASE
            WHEN E.RE_VALUE IS NOT NULL THEN E.CONSENT_VALUE
            WHEN C.CHANNEL IS NULL THEN NULL
            WHEN
                STARTSWITH(R.RE_VALUE, 'Opt In All ')
                AND ENDSWITH(R.RE_VALUE, ' ' || C.CHANNEL_LABEL) THEN 'IN'
            WHEN
                (
                    STARTSWITH(R.RE_VALUE, 'Opt Out All ')
                    OR STARTSWITH(R.RE_VALUE, 'FPS - No ')
                )
                AND ENDSWITH(R.RE_VALUE, ' ' || C.CHANNEL_LABEL) THEN 'OUT'
            WHEN
                STARTSWITH(R.RE_VALUE, 'z No ') OR STARTSWITH(R.RE_VALUE, 'No ')
                THEN 'OUT'
        END AS CONSENT_VALUE,
        E.NOTE
    FROM RE_VALUES AS R
    LEFT JOIN CHANNELS AS C ON R.RE_ATTRIBUTE_NAME = C.RE_ATTRIBUTE_NAME
    LEFT JOIN EXCEPTIONS AS E
        ON R.RE_ATTRIBUTE_NAME = E.RE_ATTRIBUTE_NAME AND R.RE_VALUE = E.RE_VALUE
)

SELECT
    RU.RE_ATTRIBUTE_NAME,
    RU.RE_VALUE,
    RU.CHANNEL,
    RU.CONSENT_TYPE,
    T.MHA_CONSENTTYPEID AS D365_CONSENT_TYPE_ID,
    RU.CONSENT_VALUE,
    CASE
        WHEN RU.IS_EXCEPTION AND RU.CONSENT_VALUE IS NULL THEN 'UNMAPPED'
        WHEN RU.CONSENT_VALUE IS NULL THEN 'NEW'
        WHEN T.MHA_CONSENTTYPEID IS NULL THEN 'TYPE_MISSING'
        ELSE 'MAPPED'
    END AS MAP_STATUS,
    RU.NOTE
FROM RULES AS RU
LEFT JOIN RAW.DYNAMICS.VW_ODS_MHA_CONSENTTYPES AS T
    ON UPPER(TRIM(RU.CONSENT_TYPE)) = UPPER(TRIM(T.MHA_NAME));