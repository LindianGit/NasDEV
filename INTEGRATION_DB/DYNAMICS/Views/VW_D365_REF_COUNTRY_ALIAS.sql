create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_REF_COUNTRY_ALIAS(
	RE_COUNTRY_NAME,
	MATCH_METHOD,
	D365_COUNTRY_NAME,
	D365_ISOCOUNTRY_ID,
	MAP_STATUS,
	NOTE
) as
-- How each RE country name resolves to a D365 ISO country (mha_isocountry). RE
-- names come from the live RE addresses, ISO countries from RAW.DYNAMICS.
-- MATCH_METHOD: NAME (same name, ignoring case), ALIAS (the decision list),
-- NONE. MAP_STATUS: MAPPED, UNMAPPED (decided: no country), EXCEPTION (no
-- match, for NAS to review: the view never guesses). The client owns the ISO
-- list, so until it is complete many names are EXCEPTION.
WITH RE_VALUES AS (
    SELECT DISTINCT TRIM(COUNTRYDESCRIPTION) AS RE_COUNTRY_NAME
    FROM RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES
    WHERE NULLIF(TRIM(COUNTRYDESCRIPTION), '') IS NOT NULL
),

ALIASES AS (
    SELECT
        COLUMN1 AS RE_COUNTRY_NAME,
        COLUMN2 AS D365_COUNTRY_NAME,
        COLUMN3 AS NOTE
    FROM VALUES
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('Eire', 'Ireland', 'Alias of the ISO name'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('Republic of Ireland', 'Ireland', 'Alias of the ISO name'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('The Netherlands', 'Netherlands', 'RE holds both spellings'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('Macedonia', 'North Macedonia', 'Former name'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('Russia', 'Russian Federation', 'Short name'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('Ivory Coast', 'Cote d''Ivoire', 'English name'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('Antigua & Barbuda', 'Antigua and Barbuda', 'Ampersand spelling'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('UK', 'United Kingdom', 'Abbreviation'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('U.K.', 'United Kingdom', 'Abbreviation'),
    -- ASSUMED: target name is an assumed ISO English short name; check against the client list
    ('Great Britain', 'United Kingdom', 'Not an ISO name'),
    -- ASSUMED: no single ISO country; left unmapped until NAS decides
    (
        'Channel Islands',
        NULL,
        'Jersey and Guernsey are separate ISO countries; NAS must say which'
    ),
    -- ASSUMED: not a country; left unmapped
    ('British Armed Forces', NULL, 'Not a country'),
    -- ASSUMED: dissolved; left unmapped
    ('Netherlands Antilles', NULL, 'Dissolved; no current ISO country'),
    ('zUnknown', NULL, 'RE placeholder for no country')
)

SELECT
    R.RE_COUNTRY_NAME,
    CASE
        WHEN I.MHA_ISOCOUNTRYID IS NOT NULL THEN 'NAME'
        WHEN A.RE_COUNTRY_NAME IS NOT NULL THEN 'ALIAS'
        ELSE 'NONE'
    END AS MATCH_METHOD,
    COALESCE(I.MHA_NAME, I2.MHA_NAME, A.D365_COUNTRY_NAME) AS D365_COUNTRY_NAME,
    COALESCE(I.MHA_ISOCOUNTRYID, I2.MHA_ISOCOUNTRYID) AS D365_ISOCOUNTRY_ID,
    CASE
        WHEN
            COALESCE(I.MHA_ISOCOUNTRYID, I2.MHA_ISOCOUNTRYID) IS NOT NULL
            THEN 'MAPPED'
        WHEN
            A.RE_COUNTRY_NAME IS NOT NULL AND A.D365_COUNTRY_NAME IS NULL
            THEN 'UNMAPPED'
        ELSE 'EXCEPTION'
    END AS MAP_STATUS,
    A.NOTE
FROM RE_VALUES AS R
LEFT JOIN RAW.DYNAMICS.VW_ODS_MHA_ISOCOUNTRIES AS I
    ON UPPER(R.RE_COUNTRY_NAME) = UPPER(TRIM(I.MHA_NAME))
LEFT JOIN ALIASES AS A
    ON UPPER(R.RE_COUNTRY_NAME) = UPPER(A.RE_COUNTRY_NAME)
LEFT JOIN RAW.DYNAMICS.VW_ODS_MHA_ISOCOUNTRIES AS I2
    ON UPPER(A.D365_COUNTRY_NAME) = UPPER(TRIM(I2.MHA_NAME));