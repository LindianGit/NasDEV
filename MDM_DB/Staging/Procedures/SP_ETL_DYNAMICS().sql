CREATE OR REPLACE PROCEDURE MDM_DB.STAGING.SP_ETL_DYNAMICS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET rows_merged     INT := 0;
    LET rows_deleted    INT := 0;
    LET rows_arrays     INT := 0;
    LET rows_backfill   INT := 0;
    LET co_rows_merged  INT := 0;
    LET co_rows_deleted INT := 0;
    LET co_rows_arrays   INT := 0;
    LET co_rows_backfill INT := 0;

    -- Contacts: MERGE
    MERGE INTO MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    USING (
        SELECT
            c.MD5_HASH                                                                          AS MD5,
            ''D365-'' || c.CONTACTID                                                               AS STANDARDISED_ID,
            ''DYNAMICS''                                                                           AS SOURCE_SYSTEM,
            c.CONTACTID::VARCHAR                                                                 AS SOURCE_RECORD_ID,
            ''INDIVIDUAL''                                                                         AS SOURCE_DOMAIN,
            NULLIF(TRIM(
                COALESCE(TRIM(c.FIRSTNAME), '''') || '' '' ||
                COALESCE(TRIM(c.MIDDLENAME), '''') || '' '' ||
                COALESCE(TRIM(c.LASTNAME), '''')
            ), '''')                                                                               AS FULL_NAME,
            INITCAP(NULLIF(TRIM(c.FIRSTNAME), ''''))                                               AS FIRST_NAME,
            INITCAP(NULLIF(TRIM(c.LASTNAME), ''''))                                                 AS LAST_NAME,
            NULLIF(LOWER(TRIM(c.EMAILADDRESS1)), '''')                                             AS EMAIL,
            COALESCE(c.MOBILEPHONE, c.TELEPHONE2, c.TELEPHONE1)                                   AS PHONE,
            NULLIF(TRIM(c.ADDRESS1_LINE1), '''')                                                    AS ADDRESS_LINE1,
            NULLIF(TRIM(c.ADDRESS1_CITY), '''')                                                     AS CITY,
            NULLIF(TRIM(c.ADDRESS1_POSTALCODE), '''')                                               AS POSTCODE,
            NULLIF(TRIM(c.ADDRESS1_COUNTRY), '''')                                                  AS COUNTRY,
            NULL::VARCHAR                                                                        AS COUNTRY_ISO2,
            INITCAP(NULLIF(TRIM(c.MIDDLENAME), ''''))                                              AS MIDDLE_NAME,
            CASE c.NAS_CONTACTTITLE
                WHEN 808680000 THEN ''Mr''
                WHEN 808680001 THEN ''Mrs''
                WHEN 808680002 THEN ''Ms''
                WHEN 808680003 THEN ''Miss''
                WHEN 808680004 THEN ''Dr''
                WHEN 808680005 THEN ''Mx''
                ELSE NULL
            END                                                                                  AS TITLE,
            NULL::VARCHAR                                                                        AS TITLE_2,
            NULL::VARCHAR                                                                        AS SUFFIX,
            NULL::VARCHAR                                                                        AS SUFFIX_2,
            CASE c.GENDERCODE WHEN ''1'' THEN ''M'' WHEN ''2'' THEN ''F'' ELSE NULL END                  AS GENDER,
            c.BIRTHDATE                                                                          AS DATE_OF_BIRTH,
            c.MSNFP_DECEASED                                                                     AS DECEASED,
            NULL::BOOLEAN                                                                        AS IS_MEMORIAL,
            NULL::VARCHAR                                                                        AS DATE_DECEASED,
            NULL::VARCHAR                                                                        AS LOOKUP_ID,
            NULLIF(TRIM(c.ADDRESS1_LINE2), '''')                                                    AS ADDRESS_LINE2,
            NULLIF(TRIM(c.ADDRESS1_LINE3), '''')                                                    AS ADDRESS_LINE3,
            NULL::VARCHAR                                                                        AS ADDRESS_LINE4,
            NULLIF(TRIM(c.ADDRESS1_STATEORPROVINCE), '''')                                          AS COUNTY,
            c.TELEPHONE2                                                                         AS HOME_PHONE,
            c.MOBILEPHONE                                                                        AS MOBILE_PHONE,
            c.TELEPHONE1                                                                         AS WORK_PHONE,
            NULL::VARCHAR                                                                        AS TELEPHONE,
            NULL::VARCHAR                                                                        AS LICENCED_USER_TYPE,
            NULL::VARCHAR                                                                        AS PROFESSIONAL_WORK_SECTOR,
            NULLIF(TRIM(c.JOBTITLE), '''')                                                          AS JOB_TITLE,
            NULL::VARCHAR                                                                        AS LEGACY_INTENDER,
            NULL::VARCHAR                                                                        AS LEGACY_PLEDGER,
            NULL::VARCHAR                                                                        AS LEGACY_CONSIDERER,
            NULL::VARCHAR                                                                        AS LEGACY_ENQUIRER,
            NULL::BOOLEAN                                                                        AS IS_MAJOR_DONOR,
            NULL::BOOLEAN                                                                        AS IS_POLITICIAN,
            NULL::BOOLEAN                                                                        AS IS_CELEBRITY,
            NULL::BOOLEAN                                                                        AS IN_MEMORY_DONATION_HONOUREE,
            NULL::BOOLEAN                                                                        AS IN_MEMORY_NEXT_OF_KIN,
            NULL::BOOLEAN                                                                        AS BENEVOLENT_FAMILY,
            NULL::BOOLEAN                                                                        AS IS_CORPORATE,
            NULL::BOOLEAN                                                                        AS NAS_BRANCH_CONTACT,
            NULL::BOOLEAN                                                                        AS PR_CASE_STUDY,
            NULL::BOOLEAN                                                                        AS STATUTORY_AUTHORITY,
            NULL::BOOLEAN                                                                        AS SPECIAL_EVENTER,
            NULL::BOOLEAN                                                                        AS TRUSTS,
            NULL::BOOLEAN                                                                        AS LEGACY_SUPPORTER,
            NULL::VARCHAR                                                                        AS SOLICIT_CODES,
            COALESCE(c.MODIFIEDON, TRY_TO_TIMESTAMP_NTZ(c.OVERRIDDENCREATEDON), c.CREATEDON)      AS LAST_UPDATED,
            NULL::BOOLEAN                                                                        AS FOUR_YEAR_RULE
        FROM RAW.DYNAMICS.ODS_CONTACTS c
        WHERE NOT c.IS_DELETED
    ) src
    ON tgt.SOURCE_SYSTEM = src.SOURCE_SYSTEM
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt.STANDARDISED_ID NOT LIKE ''D365C-%''
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

    -- Contacts: soft-delete (scoped away from D365C- prefix to avoid overlap with accounts)
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS
    SET _IS_ACTIVE = FALSE, _STANDARDISED_AT = CURRENT_TIMESTAMP()
    WHERE SOURCE_SYSTEM = ''DYNAMICS''
        AND _IS_ACTIVE = TRUE
        AND STANDARDISED_ID LIKE ''D365-%''
        AND SOURCE_RECORD_ID NOT IN (
            SELECT CONTACTID::VARCHAR FROM RAW.DYNAMICS.ODS_CONTACTS WHERE NOT IS_DELETED
        );
    rows_deleted := SQLROWCOUNT;

    -- Contacts: ALL_EMAILS / ALL_PHONES / ALL_ADDRESSES arrays UPDATE
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.ALL_EMAILS       = src.ALL_EMAILS,
        tgt.ALL_PHONES       = src.ALL_PHONES,
        tgt.ALL_ADDRESSES    = src.ALL_ADDRESSES,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            c.CONTACTID::VARCHAR AS SOURCE_RECORD_ID,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.EMAILADDRESS1, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.EMAILADDRESS1)), ''EMAIL_TYPE'', ''Primary'',   ''IS_PRIMARY'', TRUE,  ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(c.EMAILADDRESS2, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.EMAILADDRESS2)), ''EMAIL_TYPE'', ''Secondary'', ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(c.EMAILADDRESS3, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(c.EMAILADDRESS3)), ''EMAIL_TYPE'', ''Tertiary'',  ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END
            ) AS ALL_EMAILS,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.MOBILEPHONE, '''')) != ''''             THEN OBJECT_CONSTRUCT(''PHONE'', c.MOBILEPHONE,             ''PHONE_TYPE'', ''Mobile'',    ''IS_PRIMARY'', 1, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.TELEPHONE1, '''')) != ''''              THEN OBJECT_CONSTRUCT(''PHONE'', c.TELEPHONE1,              ''PHONE_TYPE'', ''Work'',      ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.TELEPHONE2, '''')) != ''''              THEN OBJECT_CONSTRUCT(''PHONE'', c.TELEPHONE2,              ''PHONE_TYPE'', ''Home'',      ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.MSNFP_FACEBOOKPROFILE, '''')) != ''''   THEN OBJECT_CONSTRUCT(''PHONE'', c.MSNFP_FACEBOOKPROFILE,   ''PHONE_TYPE'', ''Facebook'',  ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.MSNFP_INSTAGRAMPROFILE, '''')) != ''''  THEN OBJECT_CONSTRUCT(''PHONE'', c.MSNFP_INSTAGRAMPROFILE,  ''PHONE_TYPE'', ''Instagram'', ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.MSNFP_LINKEDIN, '''')) != ''''          THEN OBJECT_CONSTRUCT(''PHONE'', c.MSNFP_LINKEDIN,          ''PHONE_TYPE'', ''LinkedIn'',  ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(c.MSNFP_TWITTER, '''')) != ''''          THEN OBJECT_CONSTRUCT(''PHONE'', c.MSNFP_TWITTER,          ''PHONE_TYPE'', ''Twitter'',   ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END
            ) AS ALL_PHONES,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(c.ADDRESS1_LINE1, '''')) != '''' OR TRIM(COALESCE(c.ADDRESS1_POSTALCODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', c.ADDRESS1_LINE1, ''ADDRESS_LINE2'', c.ADDRESS1_LINE2, ''ADDRESS_LINE3'', c.ADDRESS1_LINE3,
                    ''CITY'', c.ADDRESS1_CITY, ''COUNTY'', c.ADDRESS1_STATEORPROVINCE, ''POSTCODE'', c.ADDRESS1_POSTALCODE,
                    ''COUNTRY'', c.ADDRESS1_COUNTRY, ''ADDRESS_TYPE'', ''Primary'', ''IS_PREFERRED'', 1, ''SEND_MAIL'', TRUE
                ) END,
                CASE WHEN TRIM(COALESCE(c.ADDRESS2_LINE1, '''')) != '''' OR TRIM(COALESCE(c.ADDRESS2_POSTALCODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', c.ADDRESS2_LINE1, ''ADDRESS_LINE2'', c.ADDRESS2_LINE2, ''ADDRESS_LINE3'', c.ADDRESS2_LINE3,
                    ''CITY'', c.ADDRESS2_CITY, ''COUNTY'', c.ADDRESS2_STATEORPROVINCE, ''POSTCODE'', c.ADDRESS2_POSTALCODE,
                    ''COUNTRY'', c.ADDRESS2_COUNTRY, ''ADDRESS_TYPE'', ''Secondary'', ''IS_PREFERRED'', 0, ''SEND_MAIL'', FALSE
                ) END,
                CASE WHEN TRIM(COALESCE(c.ADDRESS3_LINE1, '''')) != '''' OR TRIM(COALESCE(c.ADDRESS3_POSTALCODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', c.ADDRESS3_LINE1, ''ADDRESS_LINE2'', c.ADDRESS3_LINE2, ''ADDRESS_LINE3'', c.ADDRESS3_LINE3,
                    ''CITY'', c.ADDRESS3_CITY, ''COUNTY'', c.ADDRESS3_STATEORPROVINCE, ''POSTCODE'', c.ADDRESS3_POSTALCODE,
                    ''COUNTRY'', c.ADDRESS3_COUNTRY, ''ADDRESS_TYPE'', ''Tertiary'', ''IS_PREFERRED'', 0, ''SEND_MAIL'', FALSE
                ) END
            ) AS ALL_ADDRESSES
        FROM RAW.DYNAMICS.ODS_CONTACTS c
        WHERE NOT c.IS_DELETED
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''DYNAMICS''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.STANDARDISED_ID NOT LIKE ''D365C-%'';
    rows_arrays := SQLROWCOUNT;

    -- Contacts: backfill new fields for records whose MD5 has not changed
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.EMAIL            = src.EMAIL,
        tgt.ADDRESS_LINE1    = src.ADDRESS_LINE1,
        tgt.ADDRESS_LINE2    = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3    = src.ADDRESS_LINE3,
        tgt.CITY             = src.CITY,
        tgt.POSTCODE         = src.POSTCODE,
        tgt.COUNTY           = src.COUNTY,
        tgt.COUNTRY          = src.COUNTRY,
        tgt.GENDER           = src.GENDER,
        tgt.TITLE            = src.TITLE,
        tgt.JOB_TITLE        = src.JOB_TITLE,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            c.CONTACTID::VARCHAR                                                                 AS SOURCE_RECORD_ID,
            NULLIF(LOWER(TRIM(c.EMAILADDRESS1)), '''')                                             AS EMAIL,
            NULLIF(TRIM(c.ADDRESS1_LINE1), '''')                                                    AS ADDRESS_LINE1,
            NULLIF(TRIM(c.ADDRESS1_LINE2), '''')                                                    AS ADDRESS_LINE2,
            NULLIF(TRIM(c.ADDRESS1_LINE3), '''')                                                    AS ADDRESS_LINE3,
            NULLIF(TRIM(c.ADDRESS1_CITY), '''')                                                     AS CITY,
            NULLIF(TRIM(c.ADDRESS1_POSTALCODE), '''')                                               AS POSTCODE,
            NULLIF(TRIM(c.ADDRESS1_STATEORPROVINCE), '''')                                          AS COUNTY,
            NULLIF(TRIM(c.ADDRESS1_COUNTRY), '''')                                                  AS COUNTRY,
            CASE c.GENDERCODE WHEN ''1'' THEN ''M'' WHEN ''2'' THEN ''F'' ELSE NULL END                  AS GENDER,
            CASE c.NAS_CONTACTTITLE
                WHEN 808680000 THEN ''Mr''
                WHEN 808680001 THEN ''Mrs''
                WHEN 808680002 THEN ''Ms''
                WHEN 808680003 THEN ''Miss''
                WHEN 808680004 THEN ''Dr''
                WHEN 808680005 THEN ''Mx''
                ELSE NULL
            END                                                                                  AS TITLE,
            NULLIF(TRIM(c.JOBTITLE), '''')                                                          AS JOB_TITLE
        FROM RAW.DYNAMICS.ODS_CONTACTS c
        WHERE NOT c.IS_DELETED
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''DYNAMICS''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.STANDARDISED_ID NOT LIKE ''D365C-%''
        AND (
            tgt.EMAIL         IS DISTINCT FROM src.EMAIL
            OR tgt.ADDRESS_LINE1 IS DISTINCT FROM src.ADDRESS_LINE1
            OR tgt.ADDRESS_LINE2 IS DISTINCT FROM src.ADDRESS_LINE2
            OR tgt.ADDRESS_LINE3 IS DISTINCT FROM src.ADDRESS_LINE3
            OR tgt.CITY          IS DISTINCT FROM src.CITY
            OR tgt.POSTCODE      IS DISTINCT FROM src.POSTCODE
            OR tgt.COUNTY        IS DISTINCT FROM src.COUNTY
            OR tgt.COUNTRY       IS DISTINCT FROM src.COUNTRY
            OR tgt.GENDER        IS DISTINCT FROM src.GENDER
            OR tgt.TITLE         IS DISTINCT FROM src.TITLE
            OR tgt.JOB_TITLE     IS DISTINCT FROM src.JOB_TITLE
        );
    rows_backfill := SQLROWCOUNT;

    -- Accounts: MERGE
    MERGE INTO MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    USING (
        SELECT
            a.MD5_HASH                                                                          AS MD5,
            ''D365C-'' || a.ACCOUNTID                                                              AS STANDARDISED_ID,
            ''DYNAMICS''                                                                           AS SOURCE_SYSTEM,
            a.ACCOUNTID::VARCHAR                                                                 AS SOURCE_RECORD_ID,
            ''ORGANISATION''                                                                       AS SOURCE_DOMAIN,
            NULLIF(TRIM(a.NAME), '''')                                                             AS FULL_NAME,
            NULL::VARCHAR                                                                        AS FIRST_NAME,
            NULL::VARCHAR                                                                        AS LAST_NAME,
            NULLIF(LOWER(TRIM(a.EMAILADDRESS1)), '''')                                             AS EMAIL,
            COALESCE(a.TELEPHONE1, a.TELEPHONE2)                                                  AS PHONE,
            NULLIF(TRIM(a.ADDRESS1_LINE1), '''')                                                    AS ADDRESS_LINE1,
            NULLIF(TRIM(a.ADDRESS1_CITY), '''')                                                     AS CITY,
            NULLIF(TRIM(a.ADDRESS1_POSTALCODE), '''')                                               AS POSTCODE,
            NULLIF(TRIM(a.ADDRESS1_COUNTRY), '''')                                                  AS COUNTRY,
            NULL::VARCHAR                                                                        AS COUNTRY_ISO2,
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
            NULLIF(TRIM(a.ADDRESS1_LINE2), '''')                                                    AS ADDRESS_LINE2,
            NULLIF(TRIM(a.ADDRESS1_LINE3), '''')                                                    AS ADDRESS_LINE3,
            NULL::VARCHAR                                                                        AS ADDRESS_LINE4,
            NULLIF(TRIM(a.ADDRESS1_STATEORPROVINCE), '''')                                          AS COUNTY,
            a.TELEPHONE2                                                                         AS HOME_PHONE,
            NULL::VARCHAR                                                                        AS MOBILE_PHONE,
            a.TELEPHONE1                                                                         AS WORK_PHONE,
            NULL::VARCHAR                                                                        AS TELEPHONE,
            NULL::VARCHAR                                                                        AS LICENCED_USER_TYPE,
            NULL::VARCHAR                                                                        AS PROFESSIONAL_WORK_SECTOR,
            NULL::VARCHAR                                                                        AS JOB_TITLE,
            NULL::VARCHAR                                                                        AS LEGACY_INTENDER,
            NULL::VARCHAR                                                                        AS LEGACY_PLEDGER,
            NULL::VARCHAR                                                                        AS LEGACY_CONSIDERER,
            NULL::VARCHAR                                                                        AS LEGACY_ENQUIRER,
            NULL::BOOLEAN                                                                        AS IS_MAJOR_DONOR,
            NULL::BOOLEAN                                                                        AS IS_POLITICIAN,
            NULL::BOOLEAN                                                                        AS IS_CELEBRITY,
            NULL::BOOLEAN                                                                        AS IN_MEMORY_DONATION_HONOUREE,
            NULL::BOOLEAN                                                                        AS IN_MEMORY_NEXT_OF_KIN,
            NULL::BOOLEAN                                                                        AS BENEVOLENT_FAMILY,
            NULL::BOOLEAN                                                                        AS IS_CORPORATE,
            NULL::BOOLEAN                                                                        AS NAS_BRANCH_CONTACT,
            NULL::BOOLEAN                                                                        AS PR_CASE_STUDY,
            NULL::BOOLEAN                                                                        AS STATUTORY_AUTHORITY,
            NULL::BOOLEAN                                                                        AS SPECIAL_EVENTER,
            NULL::BOOLEAN                                                                        AS TRUSTS,
            NULL::BOOLEAN                                                                        AS LEGACY_SUPPORTER,
            NULL::VARCHAR                                                                        AS SOLICIT_CODES,
            COALESCE(a.MODIFIEDON, TRY_TO_TIMESTAMP_NTZ(a.OVERRIDDENCREATEDON), a.CREATEDON)      AS LAST_UPDATED,
            NULL::BOOLEAN                                                                        AS FOUR_YEAR_RULE
        FROM RAW.DYNAMICS.ODS_ACCOUNTS a
        WHERE NOT a.IS_DELETED
    ) src
    ON tgt.SOURCE_SYSTEM = src.SOURCE_SYSTEM
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt.STANDARDISED_ID LIKE ''D365C-%''
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

    -- Accounts: soft-delete (scoped to D365C- prefix)
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS
    SET _IS_ACTIVE = FALSE, _STANDARDISED_AT = CURRENT_TIMESTAMP()
    WHERE SOURCE_SYSTEM = ''DYNAMICS''
        AND _IS_ACTIVE = TRUE
        AND STANDARDISED_ID LIKE ''D365C-%''
        AND SOURCE_RECORD_ID NOT IN (
            SELECT ACCOUNTID::VARCHAR FROM RAW.DYNAMICS.ODS_ACCOUNTS WHERE NOT IS_DELETED
        );
    co_rows_deleted := SQLROWCOUNT;

    -- Accounts: ALL_EMAILS / ALL_PHONES / ALL_ADDRESSES arrays UPDATE
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.ALL_EMAILS       = src.ALL_EMAILS,
        tgt.ALL_PHONES       = src.ALL_PHONES,
        tgt.ALL_ADDRESSES    = src.ALL_ADDRESSES,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            a.ACCOUNTID::VARCHAR AS SOURCE_RECORD_ID,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(a.EMAILADDRESS1, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(a.EMAILADDRESS1)), ''EMAIL_TYPE'', ''Primary'',   ''IS_PRIMARY'', TRUE,  ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(a.EMAILADDRESS2, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(a.EMAILADDRESS2)), ''EMAIL_TYPE'', ''Secondary'', ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END,
                CASE WHEN TRIM(COALESCE(a.EMAILADDRESS3, '''')) != '''' THEN OBJECT_CONSTRUCT(''EMAIL'', LOWER(TRIM(a.EMAILADDRESS3)), ''EMAIL_TYPE'', ''Tertiary'',  ''IS_PRIMARY'', FALSE, ''IS_ACTIVE'', TRUE) END
            ) AS ALL_EMAILS,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(a.TELEPHONE1, '''')) != '''' THEN OBJECT_CONSTRUCT(''PHONE'', a.TELEPHONE1, ''PHONE_TYPE'', ''Work'', ''IS_PRIMARY'', 1, ''IS_ACTIVE'', 1) END,
                CASE WHEN TRIM(COALESCE(a.TELEPHONE2, '''')) != '''' THEN OBJECT_CONSTRUCT(''PHONE'', a.TELEPHONE2, ''PHONE_TYPE'', ''Home'', ''IS_PRIMARY'', 0, ''IS_ACTIVE'', 1) END
            ) AS ALL_PHONES,
            ARRAY_CONSTRUCT_COMPACT(
                CASE WHEN TRIM(COALESCE(a.ADDRESS1_LINE1, '''')) != '''' OR TRIM(COALESCE(a.ADDRESS1_POSTALCODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', a.ADDRESS1_LINE1, ''ADDRESS_LINE2'', a.ADDRESS1_LINE2, ''ADDRESS_LINE3'', a.ADDRESS1_LINE3,
                    ''CITY'', a.ADDRESS1_CITY, ''COUNTY'', a.ADDRESS1_STATEORPROVINCE, ''POSTCODE'', a.ADDRESS1_POSTALCODE,
                    ''COUNTRY'', a.ADDRESS1_COUNTRY, ''ADDRESS_TYPE'', ''Primary'', ''IS_PREFERRED'', 1, ''SEND_MAIL'', TRUE
                ) END,
                CASE WHEN TRIM(COALESCE(a.ADDRESS2_LINE1, '''')) != '''' OR TRIM(COALESCE(a.ADDRESS2_POSTALCODE, '''')) != ''''
                THEN OBJECT_CONSTRUCT(
                    ''ADDRESS_LINE1'', a.ADDRESS2_LINE1, ''ADDRESS_LINE2'', a.ADDRESS2_LINE2, ''ADDRESS_LINE3'', a.ADDRESS2_LINE3,
                    ''CITY'', a.ADDRESS2_CITY, ''COUNTY'', a.ADDRESS2_STATEORPROVINCE, ''POSTCODE'', a.ADDRESS2_POSTALCODE,
                    ''COUNTRY'', a.ADDRESS2_COUNTRY, ''ADDRESS_TYPE'', ''Secondary'', ''IS_PREFERRED'', 0, ''SEND_MAIL'', FALSE
                ) END
            ) AS ALL_ADDRESSES
        FROM RAW.DYNAMICS.ODS_ACCOUNTS a
        WHERE NOT a.IS_DELETED
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''DYNAMICS''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.STANDARDISED_ID LIKE ''D365C-%'';
    co_rows_arrays := SQLROWCOUNT;

    -- Accounts: backfill new fields for records whose MD5 has not changed
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.EMAIL            = src.EMAIL,
        tgt.ADDRESS_LINE1    = src.ADDRESS_LINE1,
        tgt.ADDRESS_LINE2    = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3    = src.ADDRESS_LINE3,
        tgt.CITY             = src.CITY,
        tgt.POSTCODE         = src.POSTCODE,
        tgt.COUNTY           = src.COUNTY,
        tgt.COUNTRY          = src.COUNTRY,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            a.ACCOUNTID::VARCHAR                                                                 AS SOURCE_RECORD_ID,
            NULLIF(LOWER(TRIM(a.EMAILADDRESS1)), '''')                                             AS EMAIL,
            NULLIF(TRIM(a.ADDRESS1_LINE1), '''')                                                    AS ADDRESS_LINE1,
            NULLIF(TRIM(a.ADDRESS1_LINE2), '''')                                                    AS ADDRESS_LINE2,
            NULLIF(TRIM(a.ADDRESS1_LINE3), '''')                                                    AS ADDRESS_LINE3,
            NULLIF(TRIM(a.ADDRESS1_CITY), '''')                                                     AS CITY,
            NULLIF(TRIM(a.ADDRESS1_POSTALCODE), '''')                                               AS POSTCODE,
            NULLIF(TRIM(a.ADDRESS1_STATEORPROVINCE), '''')                                          AS COUNTY,
            NULLIF(TRIM(a.ADDRESS1_COUNTRY), '''')                                                  AS COUNTRY
        FROM RAW.DYNAMICS.ODS_ACCOUNTS a
        WHERE NOT a.IS_DELETED
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''DYNAMICS''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.STANDARDISED_ID LIKE ''D365C-%''
        AND (
            tgt.EMAIL         IS DISTINCT FROM src.EMAIL
            OR tgt.ADDRESS_LINE1 IS DISTINCT FROM src.ADDRESS_LINE1
            OR tgt.ADDRESS_LINE2 IS DISTINCT FROM src.ADDRESS_LINE2
            OR tgt.ADDRESS_LINE3 IS DISTINCT FROM src.ADDRESS_LINE3
            OR tgt.CITY          IS DISTINCT FROM src.CITY
            OR tgt.POSTCODE      IS DISTINCT FROM src.POSTCODE
            OR tgt.COUNTY        IS DISTINCT FROM src.COUNTY
            OR tgt.COUNTRY       IS DISTINCT FROM src.COUNTRY
        );
    co_rows_backfill := SQLROWCOUNT;

    RETURN ''Dynamics ETL complete. Contacts merged: '' || rows_merged || '', deleted: '' || rows_deleted ||
        '', arrays: '' || rows_arrays || '', backfill: '' || rows_backfill ||
        '' | Accounts merged: '' || co_rows_merged || '', deleted: '' ||
        co_rows_deleted || '', arrays: '' || co_rows_arrays || '', backfill: '' || co_rows_backfill;
END;
';