CREATE OR REPLACE PROCEDURE MDM_DB.STAGING.SP_EXTRACT_MATCH_ATTRIBUTES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    -- Extraction only: flatten and normalise the matching fields into MATCH_ATTR_* tables.
    -- Matching policy (frequency caps, scores, which edges link records) lives in
    -- SP_SCORE_MATCH_CANDIDATES.
    LET rows_emails    INT := 0;
    LET rows_phones    INT := 0;
    LET rows_addresses INT := 0;
    LET rows_org_keys  INT := 0;
    LET rows_re_links  INT := 0;

    LET rows_records   INT := 0;

    TRUNCATE TABLE MDM_DB.STAGING.MATCH_ATTR_RECORDS;
    TRUNCATE TABLE MDM_DB.STAGING.MATCH_ATTR_EMAILS;
    TRUNCATE TABLE MDM_DB.STAGING.MATCH_ATTR_PHONES;
    TRUNCATE TABLE MDM_DB.STAGING.MATCH_ATTR_ADDRESSES;
    TRUNCATE TABLE MDM_DB.STAGING.MATCH_ATTR_ORG_KEYS;
    TRUNCATE TABLE MDM_DB.STAGING.MATCH_ATTR_RE_LINKS;

    CREATE OR REPLACE TEMPORARY TABLE MDM_DB.STAGING.TMP_ACTIVE_RECORDS AS
        -- Exclude placeholder/test records that would generate spurious matches
        SELECT STANDARDISED_ID, FULL_NAME, FIRST_NAME, LAST_NAME, ALL_EMAILS, ALL_PHONES, ALL_ADDRESSES, IS_ORGANISATION
        FROM MDM_DB.STAGING.STANDARDISED_RECORDS
        WHERE _IS_ACTIVE = TRUE
            AND UPPER(TRIM(COALESCE(LAST_NAME, ''''))) NOT IN (''UNKNOWN'', ''TEST'', ''ANONYMOUS'', ''NONE'', ''NULL'', ''N/A'');

    INSERT INTO MDM_DB.STAGING.MATCH_ATTR_RECORDS (STANDARDISED_ID, FIRST_NAME, LAST_NAME, IS_ORGANISATION)
    SELECT STANDARDISED_ID, FIRST_NAME, LAST_NAME, IS_ORGANISATION
    FROM MDM_DB.STAGING.TMP_ACTIVE_RECORDS;
    rows_records := SQLROWCOUNT;

    INSERT INTO MDM_DB.STAGING.MATCH_ATTR_EMAILS (STANDARDISED_ID, EMAIL, FIRST_NAME, LAST_NAME, IS_ORGANISATION)
    SELECT r.STANDARDISED_ID, LOWER(e.VALUE:EMAIL::VARCHAR), r.FIRST_NAME, r.LAST_NAME, r.IS_ORGANISATION
    FROM MDM_DB.STAGING.TMP_ACTIVE_RECORDS r,
        LATERAL FLATTEN(INPUT => r.ALL_EMAILS) e
    WHERE e.VALUE:EMAIL::VARCHAR IS NOT NULL;
    rows_emails := SQLROWCOUNT;

    INSERT INTO MDM_DB.STAGING.MATCH_ATTR_PHONES (STANDARDISED_ID, PHONE, PHONE_CLASS, FIRST_NAME, LAST_NAME, IS_ORGANISATION)
    SELECT DISTINCT r.STANDARDISED_ID,
        p.VALUE:PHONE::VARCHAR,
        -- UK mobile: 07xxxxxxxxx or +447xxxxxxxxx
        CASE WHEN REGEXP_LIKE(p.VALUE:PHONE::VARCHAR, ''^(\\\\+?447|07)[0-9]{9}$'')
             THEN ''MOBILE'' ELSE ''LANDLINE''
        END,
        r.FIRST_NAME, r.LAST_NAME, r.IS_ORGANISATION
    FROM MDM_DB.STAGING.TMP_ACTIVE_RECORDS r,
        LATERAL FLATTEN(INPUT => r.ALL_PHONES) p
    WHERE p.VALUE:PHONE::VARCHAR IS NOT NULL
        AND LENGTH(p.VALUE:PHONE::VARCHAR) >= 7;
    rows_phones := SQLROWCOUNT;

    INSERT INTO MDM_DB.STAGING.MATCH_ATTR_ADDRESSES (
        STANDARDISED_ID, FIRST_NAME, LAST_NAME, ADDRESS_LINE1, POSTCODE, IS_PREFERRED, IS_ORGANISATION,
        IS_CURRENT
    )
    SELECT r.STANDARDISED_ID, r.FIRST_NAME, r.LAST_NAME,
        a.VALUE:ADDRESS_LINE1::VARCHAR,
        a.VALUE:POSTCODE::VARCHAR,
        -- RE stores preferred as -1; normalise any non-zero value to 1
        CASE WHEN a.VALUE:IS_PREFERRED::NUMBER != 0 THEN 1 ELSE 0 END,
        r.IS_ORGANISATION,
        -- Previous when typed "Previous address" or its VALID_TO date has passed.
        NOT (COALESCE(a.VALUE:ADDRESS_TYPE::VARCHAR, '''') ILIKE ''Previous%''
             OR COALESCE(TRY_TO_TIMESTAMP_NTZ(a.VALUE:VALID_TO::VARCHAR) <= CURRENT_TIMESTAMP(), FALSE))
    FROM MDM_DB.STAGING.TMP_ACTIVE_RECORDS r,
        LATERAL FLATTEN(INPUT => r.ALL_ADDRESSES) a
    WHERE a.VALUE:POSTCODE::VARCHAR IS NOT NULL;
    rows_addresses := SQLROWCOUNT;

    -- Shared normalised org-name key: lower, trim, strip punctuation, strip common
    -- legal suffixes, strip a leading "the". NULLIF resolves empty results to NULL and
    -- those rows are dropped, so no two nameless orgs ever match (KEY-1).
    INSERT INTO MDM_DB.STAGING.MATCH_ATTR_ORG_KEYS (STANDARDISED_ID, ORG_KEY)
    SELECT STANDARDISED_ID, ORG_KEY
    FROM (
        SELECT STANDARDISED_ID,
            NULLIF(TRIM(REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            LOWER(TRIM(FULL_NAME)),
                            ''[[:punct:]]'', ''''
                        ),
                        ''\\\\b(ltd|limited|plc|llp|llc|inc|corporation|corp|co)\\\\b'', ''''
                    ),
                    ''^the\\\\s+'', ''''
                ),
                ''[[:space:]]+'', '' ''
            )), '''') AS ORG_KEY
        FROM MDM_DB.STAGING.TMP_ACTIVE_RECORDS
        WHERE IS_ORGANISATION = TRUE
    )
    WHERE ORG_KEY IS NOT NULL;
    rows_org_keys := SQLROWCOUNT;

    -- Authoritative cross-source links: HubSpot stores the RE Constituent ID on
    -- PROPERTY_CONSTITUENT_ID. ''HS-xxx'' and ''HSC-xxx'' sort before ''RE-xxx'', so the
    -- HubSpot record is always ID_A. IS_ORGANISATION guards against OBJECTID collision
    -- between contacts and companies (independent sequences).
    INSERT INTO MDM_DB.STAGING.MATCH_ATTR_RE_LINKS (STANDARDISED_ID_A, STANDARDISED_ID_B, LINK_TYPE)
    SELECT hs_sr.STANDARDISED_ID, re_sr.STANDARDISED_ID, ''CONTACT''
    FROM RAW.HUBSPOT.ODS_OBJECTS_CONTACTS hs_raw
    INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS hs_sr
        ON  hs_sr.SOURCE_RECORD_ID = hs_raw.OBJECTID::VARCHAR
        AND hs_sr.SOURCE_SYSTEM    = ''HUBSPOT''
        AND hs_sr.IS_ORGANISATION  = FALSE
        AND hs_sr._IS_ACTIVE       = TRUE
    INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS re_sr
        ON  re_sr.STANDARDISED_ID  = ''RE-'' || hs_raw.PROPERTY_CONSTITUENT_ID
        AND re_sr._IS_ACTIVE       = TRUE
    WHERE hs_raw.IS_DELETED = FALSE
        AND hs_raw.PROPERTY_CONSTITUENT_ID IS NOT NULL
        AND TRIM(hs_raw.PROPERTY_CONSTITUENT_ID) != '''';
    rows_re_links := SQLROWCOUNT;

    INSERT INTO MDM_DB.STAGING.MATCH_ATTR_RE_LINKS (STANDARDISED_ID_A, STANDARDISED_ID_B, LINK_TYPE)
    SELECT hsc_sr.STANDARDISED_ID, re_sr.STANDARDISED_ID, ''ORG''
    FROM RAW.HUBSPOT.ODS_OBJECTS_COMPANIES hsc_raw
    INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS hsc_sr
        ON  hsc_sr.SOURCE_RECORD_ID = hsc_raw.OBJECTID::VARCHAR
        AND hsc_sr.SOURCE_SYSTEM    = ''HUBSPOT''
        AND hsc_sr.IS_ORGANISATION  = TRUE
        AND hsc_sr._IS_ACTIVE       = TRUE
    INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS re_sr
        ON  re_sr.STANDARDISED_ID   = ''RE-'' || hsc_raw.PROPERTY_CONSTITUENT_ID::NUMBER(38, 0)
        AND re_sr._IS_ACTIVE        = TRUE
    WHERE hsc_raw.IS_DELETED = FALSE
        AND hsc_raw.PROPERTY_CONSTITUENT_ID IS NOT NULL
        AND TRIM(hsc_raw.PROPERTY_CONSTITUENT_ID::NUMBER(38, 0)::VARCHAR) != '''';
    rows_re_links := rows_re_links + SQLROWCOUNT;

    RETURN ''Extraction complete. Records: '' || rows_records || '', Emails: '' || rows_emails || '', Phones: '' || rows_phones
        || '', Addresses: '' || rows_addresses || '', Org keys: '' || rows_org_keys
        || '', RE links: '' || rows_re_links;
END;
';