CREATE OR REPLACE PROCEDURE MDM_DB.STAGING.SP_ETL_HUBSPOT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET rows_merged          INT := 0;
    LET rows_deleted         INT := 0;
    LET rows_arrays          INT := 0;
    LET rows_backfill        INT := 0;
    LET co_rows_merged       INT := 0;
    LET co_rows_deleted      INT := 0;
    LET co_rows_arrays       INT := 0;
    LET co_rows_backfill     INT := 0;
    LET rows_normalise       INT := 0;

    -- Contacts: MERGE
    MERGE INTO MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    USING (
        SELECT
            c.MD5_HASH                                                                          AS MD5,
            ''HS-'' || c.OBJECTID                                                                 AS STANDARDISED_ID,
            ''HUBSPOT''                                                                           AS SOURCE_SYSTEM,
            c.OBJECTID::VARCHAR                                                                 AS SOURCE_RECORD_ID,
            ''INDIVIDUAL''                                                                        AS SOURCE_DOMAIN,
            NULLIF(TRIM(
                COALESCE(c.PROPERTY_SALUTATION, '''') || '' '' ||
                CASE WHEN c.PROPERTY_FIRSTNAME   LIKE ''%@%'' THEN '''' ELSE COALESCE(c.PROPERTY_FIRSTNAME, '''') END || '' '' ||
                -- PROPERTY_MIDDLE_NAME removed from source; omitted from name concatenation
                CASE WHEN c.PROPERTY_LASTNAME    LIKE ''%@%'' THEN '''' ELSE COALESCE(c.PROPERTY_LASTNAME, '''') END
                -- PROPERTY_SUFFIX removed from source; omitted from name concatenation
            ), '''')                                                                               AS FULL_NAME,
            CASE WHEN c.PROPERTY_FIRSTNAME LIKE ''%@%'' THEN NULL ELSE INITCAP(NULLIF(TRIM(c.PROPERTY_FIRSTNAME), '''')) END AS FIRST_NAME,
            CASE WHEN c.PROPERTY_LASTNAME  LIKE ''%@%'' THEN NULL ELSE INITCAP(NULLIF(TRIM(c.PROPERTY_LASTNAME),  '''')) END AS LAST_NAME,
            LOWER(TRIM(c.PROPERTY_EMAIL))                                                       AS EMAIL,
            REGEXP_REPLACE(c.PROPERTY_PHONE, ''[^0-9+]'', '''')                                    AS PHONE,
            NULL::VARCHAR                                                                        AS ADDRESS_LINE1, -- PROPERTY_ADDRESS_LINE_1 removed from source
            INITCAP(TRIM(c.PROPERTY_CITY))                                             AS CITY,
            UPPER(TRIM(REGEXP_REPLACE(c.PROPERTY_ZIP, ''\\\\s+'', '' '')))         AS POSTCODE,
            INITCAP(TRIM(c.PROPERTY_COUNTRY_))                                    AS COUNTRY,
            NULL                                                                                AS COUNTRY_ISO2,
            -- New identity fields (contacts)
            NULL::VARCHAR                                                                        AS MIDDLE_NAME,
            NULLIF(TRIM(c.PROPERTY_TITLE), '''')                                                  AS TITLE,
            NULL::VARCHAR                                                                        AS TITLE_2,
            NULL::VARCHAR                                                                        AS SUFFIX, -- PROPERTY_SUFFIX removed from source
            NULL::VARCHAR                                                                        AS SUFFIX_2,
             NULLIF(TRIM(SUBSTR(c.PROPERTY_GENDER, 1, 1)), '''')                                  AS GENDER, -- PROPERTY_GENDER_RE replaced by PROPERTY_GENDER
            c.PROPERTY_DATE_OF_BIRTH_FORM                                                        AS DATE_OF_BIRTH, -- PROPERTY_NAS_DATE_OF_BIRTH_ replaced by PROPERTY_DATE_OF_BIRTH_FORM
            TRY_CAST(c.PROPERTY_DECEASED AS BOOLEAN)                                            AS DECEASED,
            NULL::BOOLEAN                                                                        AS IS_MEMORIAL,
            NULL::VARCHAR                                                                        AS DATE_DECEASED,
            NULL::VARCHAR                                                                        AS LOOKUP_ID,
            -- Extended address fields (contacts)
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_2))                                         AS ADDRESS_LINE2,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_3))                                         AS ADDRESS_LINE3,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_4))                                         AS ADDRESS_LINE4,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_2_COUNTY))                                           AS COUNTY,
            -- Type-specific phone fields (contacts)
            REGEXP_REPLACE(c.PROPERTY_HOME_PHONE,     ''[^0-9+]'', '''')                           AS HOME_PHONE,
            REGEXP_REPLACE(c.PROPERTY_MOBILEPHONE,    ''[^0-9+]'', '''')                           AS MOBILE_PHONE,
            REGEXP_REPLACE(c.PROPERTY_BUSINESS_PHONE, ''[^0-9+]'', '''')                           AS WORK_PHONE,
            NULL::VARCHAR                                                                        AS TELEPHONE,
            -- Attribute fields (contacts)
            NULLIF(TRIM(c.PROPERTY_LICENSED_USER_TYPE), '''')                                     AS LICENCED_USER_TYPE,
            NULLIF(TRIM(c.PROPERTY_PROFESSIONAL_WORK_SECTOR), '''')                               AS PROFESSIONAL_WORK_SECTOR,
            NULLIF(TRIM(c.PROPERTY_JOBTITLE), '''')                                               AS JOB_TITLE,
            NULLIF(TRIM(c.PROPERTY_LEGACY_INTENDER), '''')                                        AS LEGACY_INTENDER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_PLEDGER), '''')                                         AS LEGACY_PLEDGER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_CONSIDERER), '''')                                      AS LEGACY_CONSIDERER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_PLEDGER_ENQUIRER), '''')                                 AS LEGACY_ENQUIRER, -- PROPERTY_LEGACY_ENQUIRER replaced by PROPERTY_LEGACY_PLEDGER_ENQUIRER
            -- Constituent code flags (contacts)
            TRY_CAST(c.PROPERTY_IS_A_MAJOR_DONOR AS BOOLEAN)                                   AS IS_MAJOR_DONOR,
            TRY_CAST(c.PROPERTY_IS_A_POLITICIAN AS BOOLEAN)                                    AS IS_POLITICIAN,
            TRY_CAST(c.PROPERTY_CELEBRITY AS BOOLEAN)                                           AS IS_CELEBRITY, -- PROPERTY_IS_A_CELEBRITY replaced by PROPERTY_CELEBRITY
            TRY_CAST(c.PROPERTY_IN_MEMORY_DONATION_HONOUREE AS BOOLEAN)                        AS IN_MEMORY_DONATION_HONOUREE,
            TRY_CAST(c.PROPERTY_IN_MEMORY_NEXT_OF_KIN AS BOOLEAN)                              AS IN_MEMORY_NEXT_OF_KIN,
            TRY_CAST(c.PROPERTY_BENEVOLENT_FAMILY AS BOOLEAN)                                  AS BENEVOLENT_FAMILY,
            TRY_CAST(c.PROPERTY_IS_A_CORPORATE AS BOOLEAN)                                      AS IS_CORPORATE, -- PROPERTY_IS_A_COPORATE removed from source
            TRY_CAST(c.PROPERTY_NAS_BRANCH_CONTACT AS BOOLEAN)                                 AS NAS_BRANCH_CONTACT,
            TRY_CAST(c.PROPERTY_PR_CASE_STUDY AS BOOLEAN)                                      AS PR_CASE_STUDY,
            TRY_CAST(c.PROPERTY_STATUTORY_AUTHORITY AS BOOLEAN)                                AS STATUTORY_AUTHORITY,
            TRY_CAST(c.PROPERTY_SPECIAL_EVENTER AS BOOLEAN)                                    AS SPECIAL_EVENTER,
            TRY_CAST(c.PROPERTY_TRUSTS AS BOOLEAN)                                             AS TRUSTS,
            TRY_CAST(c.PROPERTY_LEGACY_SUPPORTER AS BOOLEAN)                                   AS LEGACY_SUPPORTER,
            c.PROPERTY_SOLICIT_CODES                                                            AS SOLICIT_CODES,
            COALESCE(c.PROPERTY_LASTMODIFIEDDATE, c.PROPERTY_CREATEDATE)                       AS LAST_UPDATED,
            TRY_CAST(c.PROPERTY_N4_YEAR_RULE AS BOOLEAN)                                       AS FOUR_YEAR_RULE -- boolean checkbox; HubSpot serialises as ''true''/''false''
        FROM RAW.HUBSPOT.ODS_OBJECTS_CONTACTS c
        WHERE c.IS_DELETED = FALSE
            -- CR-2026-08-03: exclude contacts explicitly flagged "Add to RE" = No
            AND (c.PROPERTY_ADD_TO_RE IS NULL OR UPPER(TRIM(c.PROPERTY_ADD_TO_RE)) != ''NO'')
    ) src
    ON tgt.SOURCE_SYSTEM = src.SOURCE_SYSTEM
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt.STANDARDISED_ID NOT LIKE ''HSC-%''
    WHEN MATCHED AND tgt.MD5 != src.MD5 THEN UPDATE SET
        tgt.MD5                       = src.MD5,
        tgt.SOURCE_DOMAIN             = src.SOURCE_DOMAIN,
        tgt.FULL_NAME                 = src.FULL_NAME,
        tgt.FIRST_NAME                = src.FIRST_NAME,
        tgt.LAST_NAME                 = src.LAST_NAME,
        tgt.EMAIL                     = src.EMAIL,
        tgt.PHONE                     = src.PHONE,
        tgt.ADDRESS_LINE1             = src.ADDRESS_LINE1,
        tgt.CITY                      = src.CITY,
        tgt.POSTCODE                  = src.POSTCODE,
        tgt.COUNTRY                   = src.COUNTRY,
        tgt.COUNTRY_ISO2              = src.COUNTRY_ISO2,
        tgt.MIDDLE_NAME               = src.MIDDLE_NAME,
        tgt.TITLE                     = src.TITLE,
        tgt.TITLE_2                   = src.TITLE_2,
        tgt.SUFFIX                    = src.SUFFIX,
        tgt.SUFFIX_2                  = src.SUFFIX_2,
        tgt.GENDER                    = src.GENDER,
        tgt.DATE_OF_BIRTH             = src.DATE_OF_BIRTH,
        tgt.DECEASED                  = src.DECEASED,
        tgt.IS_MEMORIAL               = src.IS_MEMORIAL,
        tgt.DATE_DECEASED             = src.DATE_DECEASED,
        tgt.LOOKUP_ID                 = src.LOOKUP_ID,
        tgt.ADDRESS_LINE2             = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3             = src.ADDRESS_LINE3,
        tgt.ADDRESS_LINE4             = src.ADDRESS_LINE4,
        tgt.COUNTY                    = src.COUNTY,
        tgt.HOME_PHONE                = src.HOME_PHONE,
        tgt.MOBILE_PHONE              = src.MOBILE_PHONE,
        tgt.WORK_PHONE                = src.WORK_PHONE,
        tgt.TELEPHONE                 = src.TELEPHONE,
        tgt.LICENCED_USER_TYPE        = src.LICENCED_USER_TYPE,
        tgt.PROFESSIONAL_WORK_SECTOR  = src.PROFESSIONAL_WORK_SECTOR,
        tgt.JOB_TITLE                 = src.JOB_TITLE,
        tgt.LEGACY_INTENDER           = src.LEGACY_INTENDER,
        tgt.LEGACY_PLEDGER            = src.LEGACY_PLEDGER,
        tgt.LEGACY_CONSIDERER         = src.LEGACY_CONSIDERER,
        tgt.LEGACY_ENQUIRER           = src.LEGACY_ENQUIRER,
        tgt.IS_MAJOR_DONOR            = src.IS_MAJOR_DONOR,
        tgt.IS_POLITICIAN             = src.IS_POLITICIAN,
        tgt.IS_CELEBRITY              = src.IS_CELEBRITY,
        tgt.IN_MEMORY_DONATION_HONOUREE = src.IN_MEMORY_DONATION_HONOUREE,
        tgt.IN_MEMORY_NEXT_OF_KIN     = src.IN_MEMORY_NEXT_OF_KIN,
        tgt.BENEVOLENT_FAMILY         = src.BENEVOLENT_FAMILY,
        tgt.IS_CORPORATE              = src.IS_CORPORATE,
        tgt.NAS_BRANCH_CONTACT        = src.NAS_BRANCH_CONTACT,
        tgt.PR_CASE_STUDY             = src.PR_CASE_STUDY,
        tgt.STATUTORY_AUTHORITY       = src.STATUTORY_AUTHORITY,
        tgt.SPECIAL_EVENTER           = src.SPECIAL_EVENTER,
        tgt.TRUSTS                    = src.TRUSTS,
        tgt.LEGACY_SUPPORTER          = src.LEGACY_SUPPORTER,
        tgt.SOLICIT_CODES             = src.SOLICIT_CODES,
        tgt.LAST_UPDATED              = src.LAST_UPDATED,
        tgt.FOUR_YEAR_RULE            = src.FOUR_YEAR_RULE,
        tgt._STANDARDISED_AT          = CURRENT_TIMESTAMP(),
        tgt._IS_ACTIVE                = TRUE
    WHEN NOT MATCHED THEN INSERT (
        MD5, STANDARDISED_ID, SOURCE_SYSTEM, SOURCE_RECORD_ID, SOURCE_DOMAIN,
        FULL_NAME, FIRST_NAME, LAST_NAME, EMAIL, PHONE,
        ADDRESS_LINE1, CITY, POSTCODE, COUNTRY, COUNTRY_ISO2,
        MIDDLE_NAME, TITLE, TITLE_2, SUFFIX, SUFFIX_2,
        GENDER, DATE_OF_BIRTH, DECEASED, IS_MEMORIAL, DATE_DECEASED, LOOKUP_ID,
        ADDRESS_LINE2, ADDRESS_LINE3, ADDRESS_LINE4, COUNTY,
        HOME_PHONE, MOBILE_PHONE, WORK_PHONE, TELEPHONE,
        LICENCED_USER_TYPE, PROFESSIONAL_WORK_SECTOR, JOB_TITLE,
        LEGACY_INTENDER, LEGACY_PLEDGER, LEGACY_CONSIDERER, LEGACY_ENQUIRER,
        IS_MAJOR_DONOR, IS_POLITICIAN, IS_CELEBRITY,
        IN_MEMORY_DONATION_HONOUREE, IN_MEMORY_NEXT_OF_KIN, BENEVOLENT_FAMILY,
        IS_CORPORATE, NAS_BRANCH_CONTACT, PR_CASE_STUDY,
        STATUTORY_AUTHORITY, SPECIAL_EVENTER, TRUSTS, LEGACY_SUPPORTER,
        SOLICIT_CODES, LAST_UPDATED, FOUR_YEAR_RULE, _STANDARDISED_AT, _IS_ACTIVE
    ) VALUES (
        src.MD5, src.STANDARDISED_ID, src.SOURCE_SYSTEM, src.SOURCE_RECORD_ID, src.SOURCE_DOMAIN,
        src.FULL_NAME, src.FIRST_NAME, src.LAST_NAME, src.EMAIL, src.PHONE,
        src.ADDRESS_LINE1, src.CITY, src.POSTCODE, src.COUNTRY, src.COUNTRY_ISO2,
        src.MIDDLE_NAME, src.TITLE, src.TITLE_2, src.SUFFIX, src.SUFFIX_2,
        src.GENDER, src.DATE_OF_BIRTH, src.DECEASED, src.IS_MEMORIAL, src.DATE_DECEASED, src.LOOKUP_ID,
        src.ADDRESS_LINE2, src.ADDRESS_LINE3, src.ADDRESS_LINE4, src.COUNTY,
        src.HOME_PHONE, src.MOBILE_PHONE, src.WORK_PHONE, src.TELEPHONE,
        src.LICENCED_USER_TYPE, src.PROFESSIONAL_WORK_SECTOR, src.JOB_TITLE,
        src.LEGACY_INTENDER, src.LEGACY_PLEDGER, src.LEGACY_CONSIDERER, src.LEGACY_ENQUIRER,
        src.IS_MAJOR_DONOR, src.IS_POLITICIAN, src.IS_CELEBRITY,
        src.IN_MEMORY_DONATION_HONOUREE, src.IN_MEMORY_NEXT_OF_KIN, src.BENEVOLENT_FAMILY,
        src.IS_CORPORATE, src.NAS_BRANCH_CONTACT, src.PR_CASE_STUDY,
        src.STATUTORY_AUTHORITY, src.SPECIAL_EVENTER, src.TRUSTS, src.LEGACY_SUPPORTER,
        src.SOLICIT_CODES, src.LAST_UPDATED, src.FOUR_YEAR_RULE, CURRENT_TIMESTAMP(), TRUE
    );
    rows_merged := SQLROWCOUNT;

    -- Contacts: soft-delete (scoped away from HSC- prefix to avoid overlap with companies)
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS
    SET _IS_ACTIVE = FALSE, _STANDARDISED_AT = CURRENT_TIMESTAMP()
    WHERE SOURCE_SYSTEM = ''HUBSPOT''
        AND _IS_ACTIVE = TRUE
        AND STANDARDISED_ID LIKE ''HS-%''
        AND SOURCE_RECORD_ID NOT IN (
            SELECT OBJECTID::VARCHAR FROM RAW.HUBSPOT.ODS_OBJECTS_CONTACTS
            WHERE IS_DELETED = FALSE
                -- CR-2026-08-03: contacts flagged "Add to RE" = No are treated
                -- the same as a hard delete, so a later flip to No retires
                -- an already-synced record.
                AND (PROPERTY_ADD_TO_RE IS NULL OR UPPER(TRIM(PROPERTY_ADD_TO_RE)) != ''NO'')
        );
    rows_deleted := SQLROWCOUNT;

    -- Contacts: arrays UPDATE
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.ALL_EMAILS       = src.ALL_EMAILS,
        tgt.ALL_PHONES       = src.ALL_PHONES,
        tgt.ALL_ADDRESSES    = src.ALL_ADDRESSES,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            c.OBJECTID::VARCHAR AS SOURCE_RECORD_ID,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.PROPERTY_EMAIL, '''')) != ''''           THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.PROPERTY_EMAIL)),           ''EMAIL_TYPE'', ''Primary'',   ''IS_PRIMARY'', TRUE,  ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_EMAIL_ADDRESS_2, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.PROPERTY_EMAIL_ADDRESS_2)), ''EMAIL_TYPE'', ''Secondary'', ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_EMAIL_ADDRESS_3, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.PROPERTY_EMAIL_ADDRESS_3)), ''EMAIL_TYPE'', ''Tertiary'',  ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_WORK_EMAIL, '''')) != ''''      THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.PROPERTY_WORK_EMAIL)),       ''EMAIL_TYPE'', ''Work'',      ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END
            ) AS ALL_EMAILS,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.PROPERTY_PHONE, '''')) != ''''             THEN OBJECT_CONSTRUCT(''PHONE'', REGEXP_REPLACE(c.PROPERTY_PHONE,            ''[^0-9+]'', ''''), ''PHONE_TYPE'', ''Primary'',    ''IS_PRIMARY'', 1, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_MOBILEPHONE, '''')) != ''''       THEN OBJECT_CONSTRUCT(''PHONE'', REGEXP_REPLACE(c.PROPERTY_MOBILEPHONE,      ''[^0-9+]'', ''''), ''PHONE_TYPE'', ''Mobile'',     ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_BUSINESS_PHONE, '''')) != ''''    THEN OBJECT_CONSTRUCT(''PHONE'', REGEXP_REPLACE(c.PROPERTY_BUSINESS_PHONE,   ''[^0-9+]'', ''''), ''PHONE_TYPE'', ''Business'',   ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_BUSINESS_PHONE_2, '''')) != ''''  THEN OBJECT_CONSTRUCT(''PHONE'', REGEXP_REPLACE(c.PROPERTY_BUSINESS_PHONE_2, ''[^0-9+]'', ''''), ''PHONE_TYPE'', ''Business 2'', ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_HOME_PHONE, '''')) != ''''        THEN OBJECT_CONSTRUCT(''PHONE'', REGEXP_REPLACE(c.PROPERTY_HOME_PHONE,       ''[^0-9+]'', ''''), ''PHONE_TYPE'', ''Home'',       ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END
                -- PROPERTY_HOME_PHONE_2 removed from source; entry omitted
            ) AS ALL_PHONES,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.PROPERTY_ADDRESS_1_STREET_1, '''')) != '''' OR TRIM(COALESCE(c.PROPERTY_ADDRESS_1_POSTAL_CODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', INITCAP(TRIM(c.PROPERTY_ADDRESS_1_STREET_1)),
                    ''ADDRESS_LINE2'', INITCAP(TRIM(c.PROPERTY_ADDRESS_1_STREET_2)),
                    ''ADDRESS_LINE3'', INITCAP(TRIM(c.PROPERTY_ADDRESS_1_STREET_3)),
                    ''CITY'',          INITCAP(TRIM(c.PROPERTY_ADDRESS_1_CITY)),
                    ''COUNTY'',        INITCAP(TRIM(c.PROPERTY_ADDRESS_1_STATEPROVINCE)),
                    ''POSTCODE'',      UPPER(TRIM(REGEXP_REPLACE(c.PROPERTY_ADDRESS_1_POSTAL_CODE, ''\\\\s+'', '' ''))),
                    ''COUNTRY'',       INITCAP(TRIM(c.PROPERTY_ADDRESS_1_COUNTRYREGION)),
                    ''ADDRESS_TYPE'',  ''Address 1'', ''IS_PREFERRED'', 1, ''SEND_MAIL'', TRUE
                ) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_ADDRESS_2_STREET_1, '''')) != '''' OR TRIM(COALESCE(c.PROPERTY_ADDRESS_2_POSTAL_CODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', INITCAP(TRIM(c.PROPERTY_ADDRESS_2_STREET_1)),
                    ''ADDRESS_LINE2'', INITCAP(TRIM(c.PROPERTY_ADDRESS_2_STREET_2)),
                    ''ADDRESS_LINE3'', INITCAP(TRIM(c.PROPERTY_ADDRESS_2_STREET_3)),
                    ''CITY'',          INITCAP(TRIM(c.PROPERTY_ADDRESS_2_CITY)),
                    ''COUNTY'',        INITCAP(TRIM(c.PROPERTY_ADDRESS_2_COUNTY)),
                    ''POSTCODE'',      UPPER(TRIM(REGEXP_REPLACE(c.PROPERTY_ADDRESS_2_POSTAL_CODE, ''\\\\s+'', '' ''))),
                    ''COUNTRY'',       INITCAP(TRIM(c.PROPERTY_ADDRESS_2_COUNTRY)),
                    ''ADDRESS_TYPE'',  ''Address 2'', ''IS_PREFERRED'', 0, ''SEND_MAIL'', FALSE
                ) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_ADDRESS_3_STREET_1, '''')) != '''' OR TRIM(COALESCE(c.PROPERTY_ADDRESS_3_POSTAL_CODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', INITCAP(TRIM(c.PROPERTY_ADDRESS_3_STREET_1)),
                    ''ADDRESS_LINE2'', INITCAP(TRIM(c.PROPERTY_ADDRESS_3_STREET_2)),
                    ''ADDRESS_LINE3'', INITCAP(TRIM(c.PROPERTY_ADDRESS_3_STREET_3)),
                    ''CITY'',          INITCAP(TRIM(c.PROPERTY_ADDRESS_3_CITY)),
                    ''COUNTY'',        INITCAP(TRIM(c.PROPERTY_ADDRESS_3_COUNTYREGION)),
                    ''POSTCODE'',      UPPER(TRIM(REGEXP_REPLACE(c.PROPERTY_ADDRESS_3_POSTAL_CODE, ''\\\\s+'', '' ''))),
                    ''COUNTRY'',       INITCAP(TRIM(c.PROPERTY_ADDRESS_3_COUNTRY)),
                    ''ADDRESS_TYPE'',  ''Address 3'', ''IS_PREFERRED'', 0, ''SEND_MAIL'', FALSE
                ) END
            ) AS ALL_ADDRESSES
        FROM RAW.HUBSPOT.ODS_OBJECTS_CONTACTS c
        WHERE c.IS_DELETED = FALSE
            -- CR-2026-08-03: exclude contacts explicitly flagged "Add to RE" = No
            AND (c.PROPERTY_ADD_TO_RE IS NULL OR UPPER(TRIM(c.PROPERTY_ADD_TO_RE)) != ''NO'')
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''HUBSPOT''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.STANDARDISED_ID NOT LIKE ''HSC-%'';
    rows_arrays := SQLROWCOUNT;

    -- Contacts: backfill new fields for records whose MD5 has not changed
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.TITLE                       = src.TITLE,
        tgt.SUFFIX                      = src.SUFFIX,
        tgt.GENDER                      = src.GENDER,
        tgt.DATE_OF_BIRTH               = src.DATE_OF_BIRTH,
        tgt.DECEASED                    = src.DECEASED,
        tgt.HOME_PHONE                  = src.HOME_PHONE,
        tgt.MOBILE_PHONE                = src.MOBILE_PHONE,
        tgt.WORK_PHONE                  = src.WORK_PHONE,
        tgt.ADDRESS_LINE2               = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3               = src.ADDRESS_LINE3,
        tgt.COUNTY                      = src.COUNTY,
        tgt.LICENCED_USER_TYPE          = src.LICENCED_USER_TYPE,
        tgt.PROFESSIONAL_WORK_SECTOR    = src.PROFESSIONAL_WORK_SECTOR,
        tgt.JOB_TITLE                   = src.JOB_TITLE,
        tgt.LEGACY_INTENDER             = src.LEGACY_INTENDER,
        tgt.LEGACY_PLEDGER              = src.LEGACY_PLEDGER,
        tgt.LEGACY_CONSIDERER           = src.LEGACY_CONSIDERER,
        tgt.LEGACY_ENQUIRER             = src.LEGACY_ENQUIRER,
        tgt.IS_MAJOR_DONOR              = src.IS_MAJOR_DONOR,
        tgt.IS_POLITICIAN               = src.IS_POLITICIAN,
        tgt.IS_CELEBRITY                = src.IS_CELEBRITY,
        tgt.IN_MEMORY_DONATION_HONOUREE = src.IN_MEMORY_DONATION_HONOUREE,
        tgt.IN_MEMORY_NEXT_OF_KIN       = src.IN_MEMORY_NEXT_OF_KIN,
        tgt.BENEVOLENT_FAMILY           = src.BENEVOLENT_FAMILY,
        tgt.IS_CORPORATE                = src.IS_CORPORATE,
        tgt.NAS_BRANCH_CONTACT          = src.NAS_BRANCH_CONTACT,
        tgt.PR_CASE_STUDY               = src.PR_CASE_STUDY,
        tgt.STATUTORY_AUTHORITY         = src.STATUTORY_AUTHORITY,
        tgt.SPECIAL_EVENTER             = src.SPECIAL_EVENTER,
        tgt.TRUSTS                      = src.TRUSTS,
        tgt.LEGACY_SUPPORTER            = src.LEGACY_SUPPORTER,
        tgt.SOLICIT_CODES               = src.SOLICIT_CODES,
        tgt.FOUR_YEAR_RULE              = src.FOUR_YEAR_RULE,
        tgt._STANDARDISED_AT            = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            c.OBJECTID::VARCHAR                                                    AS SOURCE_RECORD_ID,
            NULLIF(TRIM(c.PROPERTY_TITLE), '''')                                     AS TITLE,
            NULL::VARCHAR                                                           AS SUFFIX, -- PROPERTY_SUFFIX removed from source
            NULLIF(TRIM(SUBSTR(c.PROPERTY_GENDER, 1, 1)), '''')                    AS GENDER, -- PROPERTY_GENDER_RE replaced by PROPERTY_GENDER
            c.PROPERTY_DATE_OF_BIRTH_FORM                                          AS DATE_OF_BIRTH, -- PROPERTY_NAS_DATE_OF_BIRTH_ replaced by PROPERTY_DATE_OF_BIRTH_FORM
            TRY_CAST(c.PROPERTY_DECEASED AS BOOLEAN)                               AS DECEASED,
            REGEXP_REPLACE(c.PROPERTY_HOME_PHONE,     ''[^0-9+]'', '''')               AS HOME_PHONE,
            REGEXP_REPLACE(c.PROPERTY_MOBILEPHONE,    ''[^0-9+]'', '''')               AS MOBILE_PHONE,
            REGEXP_REPLACE(c.PROPERTY_BUSINESS_PHONE, ''[^0-9+]'', '''')               AS WORK_PHONE,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_2))                             AS ADDRESS_LINE2,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_3))                             AS ADDRESS_LINE3,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_2_COUNTY))                               AS COUNTY,
            NULLIF(TRIM(c.PROPERTY_LICENSED_USER_TYPE), '''')                        AS LICENCED_USER_TYPE,
            NULLIF(TRIM(c.PROPERTY_PROFESSIONAL_WORK_SECTOR), '''')                  AS PROFESSIONAL_WORK_SECTOR,
            NULLIF(TRIM(c.PROPERTY_JOBTITLE), '''')                                  AS JOB_TITLE,
            NULLIF(TRIM(c.PROPERTY_LEGACY_INTENDER), '''')                           AS LEGACY_INTENDER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_PLEDGER), '''')                            AS LEGACY_PLEDGER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_CONSIDERER), '''')                         AS LEGACY_CONSIDERER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_PLEDGER_ENQUIRER), '''')                    AS LEGACY_ENQUIRER, -- PROPERTY_LEGACY_ENQUIRER replaced by PROPERTY_LEGACY_PLEDGER_ENQUIRER
            TRY_CAST(c.PROPERTY_IS_A_MAJOR_DONOR AS BOOLEAN)                       AS IS_MAJOR_DONOR,
            TRY_CAST(c.PROPERTY_IS_A_POLITICIAN AS BOOLEAN)                        AS IS_POLITICIAN,
            TRY_CAST(c.PROPERTY_CELEBRITY AS BOOLEAN)                              AS IS_CELEBRITY, -- PROPERTY_IS_A_CELEBRITY replaced by PROPERTY_CELEBRITY
            TRY_CAST(c.PROPERTY_IN_MEMORY_DONATION_HONOUREE AS BOOLEAN)            AS IN_MEMORY_DONATION_HONOUREE,
            TRY_CAST(c.PROPERTY_IN_MEMORY_NEXT_OF_KIN AS BOOLEAN)                  AS IN_MEMORY_NEXT_OF_KIN,
            TRY_CAST(c.PROPERTY_BENEVOLENT_FAMILY AS BOOLEAN)                      AS BENEVOLENT_FAMILY,
            NULL::BOOLEAN                                                           AS IS_CORPORATE, -- PROPERTY_IS_A_COPORATE removed from source
            TRY_CAST(c.PROPERTY_NAS_BRANCH_CONTACT AS BOOLEAN)                     AS NAS_BRANCH_CONTACT,
            TRY_CAST(c.PROPERTY_PR_CASE_STUDY AS BOOLEAN)                          AS PR_CASE_STUDY,
            TRY_CAST(c.PROPERTY_STATUTORY_AUTHORITY AS BOOLEAN)                    AS STATUTORY_AUTHORITY,
            TRY_CAST(c.PROPERTY_SPECIAL_EVENTER AS BOOLEAN)                        AS SPECIAL_EVENTER,
            TRY_CAST(c.PROPERTY_TRUSTS AS BOOLEAN)                                 AS TRUSTS,
            TRY_CAST(c.PROPERTY_LEGACY_SUPPORTER AS BOOLEAN)                       AS LEGACY_SUPPORTER,
            c.PROPERTY_SOLICIT_CODES                                               AS SOLICIT_CODES,
            TRY_CAST(c.PROPERTY_N4_YEAR_RULE AS BOOLEAN)                           AS FOUR_YEAR_RULE
        FROM RAW.HUBSPOT.ODS_OBJECTS_CONTACTS c
        WHERE c.IS_DELETED = FALSE
            -- CR-2026-08-03: exclude contacts explicitly flagged "Add to RE" = No
            AND (c.PROPERTY_ADD_TO_RE IS NULL OR UPPER(TRIM(c.PROPERTY_ADD_TO_RE)) != ''NO'')
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''HUBSPOT''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.STANDARDISED_ID NOT LIKE ''HSC-%''
        AND (
            tgt.TITLE                       IS DISTINCT FROM src.TITLE
            OR tgt.SUFFIX                   IS DISTINCT FROM src.SUFFIX
            OR tgt.GENDER                   IS DISTINCT FROM src.GENDER
            OR tgt.DATE_OF_BIRTH            IS DISTINCT FROM src.DATE_OF_BIRTH
            OR tgt.DECEASED                 IS DISTINCT FROM src.DECEASED
            OR tgt.HOME_PHONE               IS DISTINCT FROM src.HOME_PHONE
            OR tgt.MOBILE_PHONE             IS DISTINCT FROM src.MOBILE_PHONE
            OR tgt.WORK_PHONE               IS DISTINCT FROM src.WORK_PHONE
            OR tgt.ADDRESS_LINE2            IS DISTINCT FROM src.ADDRESS_LINE2
            OR tgt.ADDRESS_LINE3            IS DISTINCT FROM src.ADDRESS_LINE3
            OR tgt.COUNTY                   IS DISTINCT FROM src.COUNTY
            OR tgt.LICENCED_USER_TYPE       IS DISTINCT FROM src.LICENCED_USER_TYPE
            OR tgt.PROFESSIONAL_WORK_SECTOR IS DISTINCT FROM src.PROFESSIONAL_WORK_SECTOR
            OR tgt.JOB_TITLE                IS DISTINCT FROM src.JOB_TITLE
            OR tgt.LEGACY_INTENDER          IS DISTINCT FROM src.LEGACY_INTENDER
            OR tgt.LEGACY_PLEDGER           IS DISTINCT FROM src.LEGACY_PLEDGER
            OR tgt.LEGACY_CONSIDERER        IS DISTINCT FROM src.LEGACY_CONSIDERER
            OR tgt.LEGACY_ENQUIRER          IS DISTINCT FROM src.LEGACY_ENQUIRER
            OR tgt.IS_MAJOR_DONOR           IS DISTINCT FROM src.IS_MAJOR_DONOR
            OR tgt.IS_POLITICIAN            IS DISTINCT FROM src.IS_POLITICIAN
            OR tgt.IS_CELEBRITY             IS DISTINCT FROM src.IS_CELEBRITY
            OR tgt.IN_MEMORY_DONATION_HONOUREE IS DISTINCT FROM src.IN_MEMORY_DONATION_HONOUREE
            OR tgt.IN_MEMORY_NEXT_OF_KIN    IS DISTINCT FROM src.IN_MEMORY_NEXT_OF_KIN
            OR tgt.BENEVOLENT_FAMILY        IS DISTINCT FROM src.BENEVOLENT_FAMILY
            OR tgt.IS_CORPORATE             IS DISTINCT FROM src.IS_CORPORATE
            OR tgt.NAS_BRANCH_CONTACT       IS DISTINCT FROM src.NAS_BRANCH_CONTACT
            OR tgt.PR_CASE_STUDY            IS DISTINCT FROM src.PR_CASE_STUDY
            OR tgt.STATUTORY_AUTHORITY      IS DISTINCT FROM src.STATUTORY_AUTHORITY
            OR tgt.SPECIAL_EVENTER          IS DISTINCT FROM src.SPECIAL_EVENTER
            OR tgt.TRUSTS                   IS DISTINCT FROM src.TRUSTS
            OR tgt.LEGACY_SUPPORTER         IS DISTINCT FROM src.LEGACY_SUPPORTER
            OR tgt.SOLICIT_CODES            IS DISTINCT FROM src.SOLICIT_CODES
            OR tgt.FOUR_YEAR_RULE           IS DISTINCT FROM src.FOUR_YEAR_RULE
        );
    rows_backfill := SQLROWCOUNT;

    -- Companies: MERGE
    MERGE INTO MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    USING (
        SELECT
            c.MD5_HASH                                                                          AS MD5,
            ''HSC-'' || c.OBJECTID                                                                AS STANDARDISED_ID,
            ''HUBSPOT''                                                                           AS SOURCE_SYSTEM,
            c.OBJECTID::VARCHAR                                                                 AS SOURCE_RECORD_ID,
            ''ORGANISATION''                                                                      AS SOURCE_DOMAIN,
            CASE WHEN c.PROPERTY_NAME LIKE ''%@%'' THEN NULL ELSE NULLIF(TRIM(c.PROPERTY_NAME), '''') END AS FULL_NAME,
            NULL                                                                                AS FIRST_NAME,
            NULL                                                                                AS LAST_NAME,
            LOWER(TRIM(c.PROPERTY_EMAIL))                                                       AS EMAIL,
            REGEXP_REPLACE(c.PROPERTY_PHONE, ''[^0-9+]'', '''')                                    AS PHONE,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_1))                                             AS ADDRESS_LINE1,
            INITCAP(TRIM(c.PROPERTY_CITY))                                                       AS CITY,
            UPPER(TRIM(REGEXP_REPLACE(c.PROPERTY_POSTCODE, ''\\\\s+'', '' '')))                     AS POSTCODE,
            INITCAP(TRIM(c.PROPERTY_COUNTRY))                                                    AS COUNTRY,
            NULL                                                                                AS COUNTRY_ISO2,
            -- New identity fields (companies: mostly null for individual-specific fields)
            NULL::VARCHAR                                                                        AS MIDDLE_NAME,
            NULL::VARCHAR                                                                        AS TITLE,
            NULL::VARCHAR                                                                        AS TITLE_2,
            NULL::VARCHAR                                                                        AS SUFFIX,
            NULL::VARCHAR                                                                        AS SUFFIX_2,
            NULL::VARCHAR                                                                        AS GENDER,
            NULL::VARCHAR                                                                        AS DATE_OF_BIRTH,
            NULL::BOOLEAN                                                                        AS DECEASED,
            NULL::BOOLEAN                                                                        AS IS_MEMORIAL,
            NULL::VARCHAR                                                                        AS DATE_DECEASED,
            NULL::VARCHAR                                                                        AS LOOKUP_ID,
            -- Extended address fields (companies)
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_2))                                             AS ADDRESS_LINE2,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_3))                                             AS ADDRESS_LINE3,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_4))                                             AS ADDRESS_LINE4,
            INITCAP(TRIM(c.PROPERTY_COUNTY))                                                     AS COUNTY,
            -- Phone fields (companies: phone in PROPERTY_PHONE already; no type-specific breakdown)
            NULL::VARCHAR                                                                        AS HOME_PHONE,
            NULL::VARCHAR                                                                        AS MOBILE_PHONE,
            REGEXP_REPLACE(c.PROPERTY_PHONE, ''[^0-9+]'', '''')                                    AS WORK_PHONE,
            NULL::VARCHAR                                                                        AS TELEPHONE,
            -- Attribute fields (companies)
            NULL::VARCHAR                                                                        AS LICENCED_USER_TYPE,
            NULLIF(TRIM(c.PROPERTY_PROFESSIONAL__WORK_SECTOR), '''')                             AS PROFESSIONAL_WORK_SECTOR,
            NULLIF(TRIM(c.PROPERTY_PROFESSIONAL__JOB_TITLE), '''')                               AS JOB_TITLE,
            NULLIF(TRIM(c.PROPERTY_LEGACY_INTENDER), '''')                                        AS LEGACY_INTENDER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_PLEDGER), '''')                                         AS LEGACY_PLEDGER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_CONSIDERER), '''')                                      AS LEGACY_CONSIDERER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_ENQUIRER), '''')                                        AS LEGACY_ENQUIRER,
            -- Constituent code flags (companies)
            NULL::BOOLEAN                                                                        AS IS_MAJOR_DONOR,
            TRY_CAST(c.PROPERTY_IS_A_POLITICIAN AS BOOLEAN)                                    AS IS_POLITICIAN,
            NULL::BOOLEAN                                                                        AS IS_CELEBRITY,
            TRY_CAST(c.PROPERTY_IN_MEMORY_DONATION_HONOUREE AS BOOLEAN)                        AS IN_MEMORY_DONATION_HONOUREE,
            TRY_CAST(c.PROPERTY_IN_MEMORY_NEXT_OF_KIN AS BOOLEAN)                              AS IN_MEMORY_NEXT_OF_KIN,
            TRY_CAST(c.PROPERTY_BENEVOLENT_FAMILY AS BOOLEAN)                                  AS BENEVOLENT_FAMILY,
            NULL::BOOLEAN                                                                        AS IS_CORPORATE,
            TRY_CAST(c.PROPERTY_NAS_BRANCH_CONTACT AS BOOLEAN)                                 AS NAS_BRANCH_CONTACT,
            TRY_CAST(c.PROPERTY_PR_CASE_STUDY AS BOOLEAN)                                      AS PR_CASE_STUDY,
            TRY_CAST(c.PROPERTY_STATUTORY_AUTHORITY AS BOOLEAN)                                AS STATUTORY_AUTHORITY,
            TRY_CAST(c.PROPERTY_SPECIAL_EVENTER AS BOOLEAN)                                    AS SPECIAL_EVENTER,
            TRY_CAST(c.PROPERTY_TRUSTS AS BOOLEAN)                                             AS TRUSTS,
            TRY_CAST(c.PROPERTY_LEGACY_SUPPORTER AS BOOLEAN)                                   AS LEGACY_SUPPORTER,
            c.PROPERTY_SOLICIT_CODES                                                            AS SOLICIT_CODES,
            COALESCE(c.PROPERTY_HS_LASTMODIFIEDDATE, c.PROPERTY_CREATEDATE)                   AS LAST_UPDATED,
            TRY_CAST(c.PROPERTY_N4_YEAR_RULE AS BOOLEAN)                                       AS FOUR_YEAR_RULE -- boolean checkbox; HubSpot serialises as ''true''/''false''
        FROM RAW.HUBSPOT.ODS_OBJECTS_COMPANIES c
        WHERE c.IS_DELETED = FALSE
    ) src
    ON tgt.SOURCE_SYSTEM = src.SOURCE_SYSTEM
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt.STANDARDISED_ID LIKE ''HSC-%''
    WHEN MATCHED AND tgt.MD5 != src.MD5 THEN UPDATE SET
        tgt.MD5                       = src.MD5,
        tgt.SOURCE_DOMAIN             = src.SOURCE_DOMAIN,
        tgt.FULL_NAME                 = src.FULL_NAME,
        tgt.FIRST_NAME                = src.FIRST_NAME,
        tgt.LAST_NAME                 = src.LAST_NAME,
        tgt.EMAIL                     = src.EMAIL,
        tgt.PHONE                     = src.PHONE,
        tgt.ADDRESS_LINE1             = src.ADDRESS_LINE1,
        tgt.CITY                      = src.CITY,
        tgt.POSTCODE                  = src.POSTCODE,
        tgt.COUNTRY                   = src.COUNTRY,
        tgt.COUNTRY_ISO2              = src.COUNTRY_ISO2,
        tgt.MIDDLE_NAME               = src.MIDDLE_NAME,
        tgt.TITLE                     = src.TITLE,
        tgt.TITLE_2                   = src.TITLE_2,
        tgt.SUFFIX                    = src.SUFFIX,
        tgt.SUFFIX_2                  = src.SUFFIX_2,
        tgt.GENDER                    = src.GENDER,
        tgt.DATE_OF_BIRTH             = src.DATE_OF_BIRTH,
        tgt.DECEASED                  = src.DECEASED,
        tgt.IS_MEMORIAL               = src.IS_MEMORIAL,
        tgt.DATE_DECEASED             = src.DATE_DECEASED,
        tgt.LOOKUP_ID                 = src.LOOKUP_ID,
        tgt.ADDRESS_LINE2             = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3             = src.ADDRESS_LINE3,
        tgt.ADDRESS_LINE4             = src.ADDRESS_LINE4,
        tgt.COUNTY                    = src.COUNTY,
        tgt.HOME_PHONE                = src.HOME_PHONE,
        tgt.MOBILE_PHONE              = src.MOBILE_PHONE,
        tgt.WORK_PHONE                = src.WORK_PHONE,
        tgt.TELEPHONE                 = src.TELEPHONE,
        tgt.LICENCED_USER_TYPE        = src.LICENCED_USER_TYPE,
        tgt.PROFESSIONAL_WORK_SECTOR  = src.PROFESSIONAL_WORK_SECTOR,
        tgt.JOB_TITLE                 = src.JOB_TITLE,
        tgt.LEGACY_INTENDER           = src.LEGACY_INTENDER,
        tgt.LEGACY_PLEDGER            = src.LEGACY_PLEDGER,
        tgt.LEGACY_CONSIDERER         = src.LEGACY_CONSIDERER,
        tgt.LEGACY_ENQUIRER           = src.LEGACY_ENQUIRER,
        tgt.IS_MAJOR_DONOR            = src.IS_MAJOR_DONOR,
        tgt.IS_POLITICIAN             = src.IS_POLITICIAN,
        tgt.IS_CELEBRITY              = src.IS_CELEBRITY,
        tgt.IN_MEMORY_DONATION_HONOUREE = src.IN_MEMORY_DONATION_HONOUREE,
        tgt.IN_MEMORY_NEXT_OF_KIN     = src.IN_MEMORY_NEXT_OF_KIN,
        tgt.BENEVOLENT_FAMILY         = src.BENEVOLENT_FAMILY,
        tgt.IS_CORPORATE              = src.IS_CORPORATE,
        tgt.NAS_BRANCH_CONTACT        = src.NAS_BRANCH_CONTACT,
        tgt.PR_CASE_STUDY             = src.PR_CASE_STUDY,
        tgt.STATUTORY_AUTHORITY       = src.STATUTORY_AUTHORITY,
        tgt.SPECIAL_EVENTER           = src.SPECIAL_EVENTER,
        tgt.TRUSTS                    = src.TRUSTS,
        tgt.LEGACY_SUPPORTER          = src.LEGACY_SUPPORTER,
        tgt.SOLICIT_CODES             = src.SOLICIT_CODES,
        tgt.LAST_UPDATED              = src.LAST_UPDATED,
        tgt.FOUR_YEAR_RULE            = src.FOUR_YEAR_RULE,
        tgt._STANDARDISED_AT          = CURRENT_TIMESTAMP(),
        tgt._IS_ACTIVE                = TRUE
    WHEN NOT MATCHED THEN INSERT (
        MD5, STANDARDISED_ID, SOURCE_SYSTEM, SOURCE_RECORD_ID, SOURCE_DOMAIN,
        FULL_NAME, FIRST_NAME, LAST_NAME, EMAIL, PHONE,
        ADDRESS_LINE1, CITY, POSTCODE, COUNTRY, COUNTRY_ISO2,
        MIDDLE_NAME, TITLE, TITLE_2, SUFFIX, SUFFIX_2,
        GENDER, DATE_OF_BIRTH, DECEASED, IS_MEMORIAL, DATE_DECEASED, LOOKUP_ID,
        ADDRESS_LINE2, ADDRESS_LINE3, ADDRESS_LINE4, COUNTY,
        HOME_PHONE, MOBILE_PHONE, WORK_PHONE, TELEPHONE,
        LICENCED_USER_TYPE, PROFESSIONAL_WORK_SECTOR, JOB_TITLE,
        LEGACY_INTENDER, LEGACY_PLEDGER, LEGACY_CONSIDERER, LEGACY_ENQUIRER,
        IS_MAJOR_DONOR, IS_POLITICIAN, IS_CELEBRITY,
        IN_MEMORY_DONATION_HONOUREE, IN_MEMORY_NEXT_OF_KIN, BENEVOLENT_FAMILY,
        IS_CORPORATE, NAS_BRANCH_CONTACT, PR_CASE_STUDY,
        STATUTORY_AUTHORITY, SPECIAL_EVENTER, TRUSTS, LEGACY_SUPPORTER,
        SOLICIT_CODES, LAST_UPDATED, FOUR_YEAR_RULE, _STANDARDISED_AT, _IS_ACTIVE
    ) VALUES (
        src.MD5, src.STANDARDISED_ID, src.SOURCE_SYSTEM, src.SOURCE_RECORD_ID, src.SOURCE_DOMAIN,
        src.FULL_NAME, src.FIRST_NAME, src.LAST_NAME, src.EMAIL, src.PHONE,
        src.ADDRESS_LINE1, src.CITY, src.POSTCODE, src.COUNTRY, src.COUNTRY_ISO2,
        src.MIDDLE_NAME, src.TITLE, src.TITLE_2, src.SUFFIX, src.SUFFIX_2,
        src.GENDER, src.DATE_OF_BIRTH, src.DECEASED, src.IS_MEMORIAL, src.DATE_DECEASED, src.LOOKUP_ID,
        src.ADDRESS_LINE2, src.ADDRESS_LINE3, src.ADDRESS_LINE4, src.COUNTY,
        src.HOME_PHONE, src.MOBILE_PHONE, src.WORK_PHONE, src.TELEPHONE,
        src.LICENCED_USER_TYPE, src.PROFESSIONAL_WORK_SECTOR, src.JOB_TITLE,
        src.LEGACY_INTENDER, src.LEGACY_PLEDGER, src.LEGACY_CONSIDERER, src.LEGACY_ENQUIRER,
        src.IS_MAJOR_DONOR, src.IS_POLITICIAN, src.IS_CELEBRITY,
        src.IN_MEMORY_DONATION_HONOUREE, src.IN_MEMORY_NEXT_OF_KIN, src.BENEVOLENT_FAMILY,
        src.IS_CORPORATE, src.NAS_BRANCH_CONTACT, src.PR_CASE_STUDY,
        src.STATUTORY_AUTHORITY, src.SPECIAL_EVENTER, src.TRUSTS, src.LEGACY_SUPPORTER,
        src.SOLICIT_CODES, src.LAST_UPDATED, src.FOUR_YEAR_RULE, CURRENT_TIMESTAMP(), TRUE
    );
    co_rows_merged := SQLROWCOUNT;

    -- Companies: soft-delete (scoped to HSC- prefix)
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS
    SET _IS_ACTIVE = FALSE, _STANDARDISED_AT = CURRENT_TIMESTAMP()
    WHERE SOURCE_SYSTEM = ''HUBSPOT''
        AND _IS_ACTIVE = TRUE
        AND STANDARDISED_ID LIKE ''HSC-%''
        AND SOURCE_RECORD_ID NOT IN (
            SELECT OBJECTID::VARCHAR FROM RAW.HUBSPOT.ODS_OBJECTS_COMPANIES WHERE IS_DELETED = FALSE
        );
    co_rows_deleted := SQLROWCOUNT;

    -- Companies: arrays UPDATE
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.ALL_EMAILS       = src.ALL_EMAILS,
        tgt.ALL_PHONES       = src.ALL_PHONES,
        tgt.ALL_ADDRESSES    = src.ALL_ADDRESSES,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            c.OBJECTID::VARCHAR AS SOURCE_RECORD_ID,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.PROPERTY_EMAIL, '''')) != ''''           THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.PROPERTY_EMAIL)),           ''EMAIL_TYPE'', ''Primary'',   ''IS_PRIMARY'', TRUE,  ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_EMAIL_ADDRESS_2, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.PROPERTY_EMAIL_ADDRESS_2)), ''EMAIL_TYPE'', ''Secondary'', ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_EMAIL_ADDRESS_3, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.PROPERTY_EMAIL_ADDRESS_3)), ''EMAIL_TYPE'', ''Tertiary'',  ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END
            ) AS ALL_EMAILS,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.PROPERTY_PHONE, '''')) != '''' THEN OBJECT_CONSTRUCT(''PHONE'', REGEXP_REPLACE(c.PROPERTY_PHONE, ''[^0-9+]'', ''''), ''PHONE_TYPE'', ''Primary'', ''IS_PRIMARY'', 1, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_FAX,   '''')) != '''' THEN OBJECT_CONSTRUCT(''PHONE'', REGEXP_REPLACE(c.PROPERTY_FAX,   ''[^0-9+]'', ''''), ''PHONE_TYPE'', ''Fax'',     ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END
            ) AS ALL_PHONES,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.PROPERTY_ADDRESS_LINE_1, '''')) != '''' OR TRIM(COALESCE(c.PROPERTY_POSTCODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_1)),
                    ''ADDRESS_LINE2'', INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_2)),
                    ''ADDRESS_LINE3'', INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_3)),
                    ''ADDRESS_LINE4'', INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_4)),
                    ''CITY'',          INITCAP(TRIM(c.PROPERTY_CITY)),
                    ''POSTCODE'',      UPPER(TRIM(REGEXP_REPLACE(c.PROPERTY_POSTCODE, ''\\\\s+'', '' ''))),
                    ''COUNTRY'',       INITCAP(TRIM(c.PROPERTY_COUNTRY)),
                    ''ADDRESS_TYPE'',  ''Primary'', ''IS_PREFERRED'', 1, ''SEND_MAIL'', TRUE
                ) END,
                CASE WHEN TRIM(COALESCE(c.PROPERTY_ADDRESS_1_STREET_1, '''')) != '''' OR TRIM(COALESCE(c.PROPERTY_ADDRESS_1_POSTAL_CODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', INITCAP(TRIM(c.PROPERTY_ADDRESS_1_STREET_1)),
                    ''ADDRESS_LINE2'', INITCAP(TRIM(c.PROPERTY_ADDRESS_1_STREET_2)),
                    ''ADDRESS_LINE3'', INITCAP(TRIM(c.PROPERTY_ADDRESS_1_STREET_3)),
                    ''CITY'',          INITCAP(TRIM(c.PROPERTY_ADDRESS_1_CITY)),
                    ''COUNTY'',        INITCAP(TRIM(c.PROPERTY_ADDRESS_1_COUNTYREGION)),
                    ''POSTCODE'',      UPPER(TRIM(REGEXP_REPLACE(c.PROPERTY_ADDRESS_1_POSTAL_CODE, ''\\\\s+'', '' ''))),
                    ''COUNTRY'',       INITCAP(TRIM(c.PROPERTY_ADDRESS_1_COUNTRY)),
                    ''ADDRESS_TYPE'',  ''Address 1'', ''IS_PREFERRED'', 0, ''SEND_MAIL'', FALSE
                ) END
            ) AS ALL_ADDRESSES
        FROM RAW.HUBSPOT.ODS_OBJECTS_COMPANIES c
        WHERE c.IS_DELETED = FALSE
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''HUBSPOT''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.STANDARDISED_ID LIKE ''HSC-%'';
    co_rows_arrays := SQLROWCOUNT;

    -- Companies: backfill new fields for records whose MD5 has not changed
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.ADDRESS_LINE2               = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3               = src.ADDRESS_LINE3,
        tgt.ADDRESS_LINE4               = src.ADDRESS_LINE4,
        tgt.COUNTY                      = src.COUNTY,
        tgt.WORK_PHONE                  = src.WORK_PHONE,
        tgt.PROFESSIONAL_WORK_SECTOR    = src.PROFESSIONAL_WORK_SECTOR,
        tgt.JOB_TITLE                   = src.JOB_TITLE,
        tgt.LEGACY_INTENDER             = src.LEGACY_INTENDER,
        tgt.LEGACY_PLEDGER              = src.LEGACY_PLEDGER,
        tgt.LEGACY_CONSIDERER           = src.LEGACY_CONSIDERER,
        tgt.LEGACY_ENQUIRER             = src.LEGACY_ENQUIRER,
        tgt.IS_POLITICIAN               = src.IS_POLITICIAN,
        tgt.IN_MEMORY_DONATION_HONOUREE = src.IN_MEMORY_DONATION_HONOUREE,
        tgt.IN_MEMORY_NEXT_OF_KIN       = src.IN_MEMORY_NEXT_OF_KIN,
        tgt.BENEVOLENT_FAMILY           = src.BENEVOLENT_FAMILY,
        tgt.NAS_BRANCH_CONTACT          = src.NAS_BRANCH_CONTACT,
        tgt.PR_CASE_STUDY               = src.PR_CASE_STUDY,
        tgt.STATUTORY_AUTHORITY         = src.STATUTORY_AUTHORITY,
        tgt.SPECIAL_EVENTER             = src.SPECIAL_EVENTER,
        tgt.TRUSTS                      = src.TRUSTS,
        tgt.LEGACY_SUPPORTER            = src.LEGACY_SUPPORTER,
        tgt.SOLICIT_CODES               = src.SOLICIT_CODES,
        tgt.FOUR_YEAR_RULE              = src.FOUR_YEAR_RULE,
        tgt._STANDARDISED_AT            = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            c.OBJECTID::VARCHAR                                                    AS SOURCE_RECORD_ID,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_2))                                 AS ADDRESS_LINE2,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_3))                                 AS ADDRESS_LINE3,
            INITCAP(TRIM(c.PROPERTY_ADDRESS_LINE_4))                                 AS ADDRESS_LINE4,
            INITCAP(TRIM(c.PROPERTY_COUNTY))                                         AS COUNTY,
            REGEXP_REPLACE(c.PROPERTY_PHONE, ''[^0-9+]'', '''')                        AS WORK_PHONE,
            NULLIF(TRIM(c.PROPERTY_PROFESSIONAL__WORK_SECTOR), '''')                 AS PROFESSIONAL_WORK_SECTOR,
            NULLIF(TRIM(c.PROPERTY_PROFESSIONAL__JOB_TITLE), '''')                   AS JOB_TITLE,
            NULLIF(TRIM(c.PROPERTY_LEGACY_INTENDER), '''')                           AS LEGACY_INTENDER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_PLEDGER), '''')                            AS LEGACY_PLEDGER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_CONSIDERER), '''')                         AS LEGACY_CONSIDERER,
            NULLIF(TRIM(c.PROPERTY_LEGACY_ENQUIRER), '''')                           AS LEGACY_ENQUIRER,
            TRY_CAST(c.PROPERTY_IS_A_POLITICIAN AS BOOLEAN)                        AS IS_POLITICIAN,
            TRY_CAST(c.PROPERTY_IN_MEMORY_DONATION_HONOUREE AS BOOLEAN)            AS IN_MEMORY_DONATION_HONOUREE,
            TRY_CAST(c.PROPERTY_IN_MEMORY_NEXT_OF_KIN AS BOOLEAN)                  AS IN_MEMORY_NEXT_OF_KIN,
            TRY_CAST(c.PROPERTY_BENEVOLENT_FAMILY AS BOOLEAN)                      AS BENEVOLENT_FAMILY,
            TRY_CAST(c.PROPERTY_NAS_BRANCH_CONTACT AS BOOLEAN)                     AS NAS_BRANCH_CONTACT,
            TRY_CAST(c.PROPERTY_PR_CASE_STUDY AS BOOLEAN)                          AS PR_CASE_STUDY,
            TRY_CAST(c.PROPERTY_STATUTORY_AUTHORITY AS BOOLEAN)                    AS STATUTORY_AUTHORITY,
            TRY_CAST(c.PROPERTY_SPECIAL_EVENTER AS BOOLEAN)                        AS SPECIAL_EVENTER,
            TRY_CAST(c.PROPERTY_TRUSTS AS BOOLEAN)                                 AS TRUSTS,
            TRY_CAST(c.PROPERTY_LEGACY_SUPPORTER AS BOOLEAN)                       AS LEGACY_SUPPORTER,
            c.PROPERTY_SOLICIT_CODES                                               AS SOLICIT_CODES,
            TRY_CAST(c.PROPERTY_N4_YEAR_RULE AS BOOLEAN)                           AS FOUR_YEAR_RULE
        FROM RAW.HUBSPOT.ODS_OBJECTS_COMPANIES c
        WHERE c.IS_DELETED = FALSE
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''HUBSPOT''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.STANDARDISED_ID LIKE ''HSC-%''
        AND (
            tgt.ADDRESS_LINE2               IS DISTINCT FROM src.ADDRESS_LINE2
            OR tgt.ADDRESS_LINE3            IS DISTINCT FROM src.ADDRESS_LINE3
            OR tgt.ADDRESS_LINE4            IS DISTINCT FROM src.ADDRESS_LINE4
            OR tgt.COUNTY                   IS DISTINCT FROM src.COUNTY
            OR tgt.WORK_PHONE               IS DISTINCT FROM src.WORK_PHONE
            OR tgt.PROFESSIONAL_WORK_SECTOR IS DISTINCT FROM src.PROFESSIONAL_WORK_SECTOR
            OR tgt.JOB_TITLE                IS DISTINCT FROM src.JOB_TITLE
            OR tgt.LEGACY_INTENDER          IS DISTINCT FROM src.LEGACY_INTENDER
            OR tgt.LEGACY_PLEDGER           IS DISTINCT FROM src.LEGACY_PLEDGER
            OR tgt.LEGACY_CONSIDERER        IS DISTINCT FROM src.LEGACY_CONSIDERER
            OR tgt.LEGACY_ENQUIRER          IS DISTINCT FROM src.LEGACY_ENQUIRER
            OR tgt.IS_POLITICIAN            IS DISTINCT FROM src.IS_POLITICIAN
            OR tgt.IN_MEMORY_DONATION_HONOUREE IS DISTINCT FROM src.IN_MEMORY_DONATION_HONOUREE
            OR tgt.IN_MEMORY_NEXT_OF_KIN    IS DISTINCT FROM src.IN_MEMORY_NEXT_OF_KIN
            OR tgt.BENEVOLENT_FAMILY        IS DISTINCT FROM src.BENEVOLENT_FAMILY
            OR tgt.NAS_BRANCH_CONTACT       IS DISTINCT FROM src.NAS_BRANCH_CONTACT
            OR tgt.PR_CASE_STUDY            IS DISTINCT FROM src.PR_CASE_STUDY
            OR tgt.STATUTORY_AUTHORITY      IS DISTINCT FROM src.STATUTORY_AUTHORITY
            OR tgt.SPECIAL_EVENTER          IS DISTINCT FROM src.SPECIAL_EVENTER
            OR tgt.TRUSTS                   IS DISTINCT FROM src.TRUSTS
            OR tgt.LEGACY_SUPPORTER         IS DISTINCT FROM src.LEGACY_SUPPORTER
            OR tgt.SOLICIT_CODES            IS DISTINCT FROM src.SOLICIT_CODES
            OR tgt.FOUR_YEAR_RULE           IS DISTINCT FROM src.FOUR_YEAR_RULE
        );
    co_rows_backfill := SQLROWCOUNT;

    -- Normalisation pass: re-apply INITCAP to name and address fields on rows
    -- loaded before the UPPER->INITCAP change.  Contacts need FIRST_NAME and
    -- LAST_NAME as well as address fields; companies need address fields only.
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS
    SET
        FIRST_NAME    = INITCAP(TRIM(FIRST_NAME)),
        LAST_NAME     = INITCAP(TRIM(LAST_NAME)),
        ADDRESS_LINE1 = INITCAP(TRIM(ADDRESS_LINE1)),
        ADDRESS_LINE2 = INITCAP(TRIM(ADDRESS_LINE2)),
        ADDRESS_LINE3 = INITCAP(TRIM(ADDRESS_LINE3)),
        ADDRESS_LINE4 = INITCAP(TRIM(ADDRESS_LINE4)),
        CITY          = INITCAP(TRIM(CITY)),
        COUNTY        = INITCAP(TRIM(COUNTY)),
        COUNTRY       = INITCAP(TRIM(COUNTRY))
    WHERE SOURCE_SYSTEM = ''HUBSPOT''
        AND _IS_ACTIVE = TRUE
        AND (
            FIRST_NAME IS DISTINCT FROM INITCAP(TRIM(FIRST_NAME))
            OR LAST_NAME IS DISTINCT FROM INITCAP(TRIM(LAST_NAME))
            OR ADDRESS_LINE1 IS DISTINCT FROM INITCAP(TRIM(ADDRESS_LINE1))
            OR ADDRESS_LINE2 IS DISTINCT FROM INITCAP(TRIM(ADDRESS_LINE2))
            OR ADDRESS_LINE3 IS DISTINCT FROM INITCAP(TRIM(ADDRESS_LINE3))
            OR ADDRESS_LINE4 IS DISTINCT FROM INITCAP(TRIM(ADDRESS_LINE4))
            OR CITY IS DISTINCT FROM INITCAP(TRIM(CITY))
            OR COUNTY IS DISTINCT FROM INITCAP(TRIM(COUNTY))
            OR COUNTRY IS DISTINCT FROM INITCAP(TRIM(COUNTRY))
        );
    rows_normalise := SQLROWCOUNT;

    RETURN ''HS ETL complete. Contacts merged: '' || rows_merged || '', deleted: '' || rows_deleted || '', arrays: '' || rows_arrays || '', backfill: '' || rows_backfill ||
           '' | Companies merged: '' || co_rows_merged || '', deleted: '' || co_rows_deleted || '', arrays: '' || co_rows_arrays || '', backfill: '' || co_rows_backfill ||
           '' | Normalised: '' || rows_normalise;
END;
';