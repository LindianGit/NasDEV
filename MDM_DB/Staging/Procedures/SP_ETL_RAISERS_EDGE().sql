CREATE OR REPLACE PROCEDURE MDM_DB.STAGING.SP_ETL_RAISERS_EDGE()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET rows_merged          INT := 0;
    LET rows_deleted         INT := 0;
    LET rows_arrays          INT := 0;
    LET rows_four_year_rule  INT := 0;
    LET rows_attributes      INT := 0;
    LET rows_codes           INT := 0;
    LET rows_solicit         INT := 0;
    LET rows_identity        INT := 0;
    LET rows_normalise       INT := 0;

    MERGE INTO MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    USING (
        SELECT
            c.MD5_HASH                                                                                      AS MD5,
            ''RE-'' || c.CONSTITUENT_ID                                                                       AS STANDARDISED_ID,
            ''RAISERS_EDGE''                                                                                  AS SOURCE_SYSTEM,
            c.CONSTITUENT_ID                                                                                AS SOURCE_RECORD_ID,
            CASE WHEN c.ISORGANISATION = TRUE THEN ''ORGANISATION'' ELSE ''INDIVIDUAL'' END                    AS SOURCE_DOMAIN,
            CASE
                WHEN c.ISORGANISATION = TRUE
                    THEN CASE
                        WHEN UPPER(TRIM(COALESCE(c.ORGANISATIONNAME, ''''))) IN ('''', ''UNKNOWN'') THEN NULL
                        ELSE TRIM(c.ORGANISATIONNAME)
                    END
                ELSE NULLIF(TRIM(INITCAP(
                    COALESCE(c.TITLE1, '''') || '' '' ||
                    CASE WHEN c.FIRST_NAME  LIKE ''%@%'' THEN '''' ELSE COALESCE(c.FIRST_NAME, '''') END || '' '' ||
                    CASE WHEN c.MIDDLE_NAME LIKE ''%@%'' THEN '''' ELSE COALESCE(c.MIDDLE_NAME, '''') END || '' '' ||
                    CASE WHEN c.LAST_NAME   LIKE ''%@%'' THEN '''' ELSE COALESCE(c.LAST_NAME, '''') END || '' '' ||
                    COALESCE(c.SUFFIX1, '''')
                )), '''')
            END                                                                                             AS FULL_NAME,
            CASE WHEN c.FIRST_NAME LIKE ''%@%'' THEN NULL ELSE INITCAP(NULLIF(TRIM(c.FIRST_NAME), '''')) END   AS FIRST_NAME,
            CASE WHEN c.LAST_NAME  LIKE ''%@%'' THEN NULL ELSE INITCAP(NULLIF(TRIM(c.LAST_NAME),  '''')) END   AS LAST_NAME,
            LOWER(TRIM(e.EMAILADDRESS))                                                                     AS EMAIL,
            p.PHONENUMBER                                                                                   AS PHONE,
            INITCAP(TRIM(a.ADDRESSLINE1))                                                                     AS ADDRESS_LINE1,
            INITCAP(TRIM(a.CITY))                                                                             AS CITY,
            a.POSTCODE                                                                                      AS POSTCODE,
            INITCAP(TRIM(a.COUNTRYDESCRIPTION))                                                               AS COUNTRY,
            NULL                                                                                            AS COUNTRY_ISO2,
            -- New identity fields
            CASE WHEN c.MIDDLE_NAME LIKE ''%@%'' THEN NULL ELSE INITCAP(NULLIF(TRIM(c.MIDDLE_NAME), '''')) END  AS MIDDLE_NAME,
            NULLIF(TRIM(c.TITLE1), '''')                                                                      AS TITLE,
            NULLIF(TRIM(c.TITLE2), '''')                                                                      AS TITLE_2,
            NULLIF(TRIM(c.SUFFIX1), '''')                                                                     AS SUFFIX,
            NULLIF(TRIM(c.SUFFIX2), '''')                                                                     AS SUFFIX_2,
            c.GENDER                                                                                        AS GENDER,
            c.DOB                                                                                           AS DATE_OF_BIRTH,
            c.DECEASED::BOOLEAN                                                                             AS DECEASED,
            c.ISHONOURMEMORIAL::BOOLEAN                                                                     AS IS_MEMORIAL,
            c.DATEDECEASED                                                                                  AS DATE_DECEASED,
            NULLIF(TRIM(c.IMPORTID), '''')                                                                    AS LOOKUP_ID,
            -- Extended address fields
            INITCAP(TRIM(a.ADDRESSLINE2))                                                                     AS ADDRESS_LINE2,
            INITCAP(TRIM(a.ADDRESSLINE3))                                                                     AS ADDRESS_LINE3,
            INITCAP(TRIM(a.ADDRESSLINE4))                                                                     AS ADDRESS_LINE4,
            INITCAP(TRIM(a.COUNTYDESCRIPTION))                                                                AS COUNTY,
            -- Type-specific phone fields
            hp.PHONENUMBER                                                                                   AS HOME_PHONE,
            mp.PHONENUMBER                                                                                   AS MOBILE_PHONE,
            wp.PHONENUMBER                                                                                   AS WORK_PHONE,
            tel.PHONENUMBER                                                                                  AS TELEPHONE,
            TRY_TO_TIMESTAMP_NTZ(COALESCE(c.DATECHANGED, c.DATEADDED))                                     AS LAST_UPDATED,
            -- CHANGEDBY: echo suppression marker.  When this equals the dedicated RE
            -- writeback user identity, LAST_UPDATED is not advanced on merge so the
            -- pipeline''s own write never beats a genuine edit on another source.
            -- Replace ''RE_API_WRITEBACK'' with the actual Sky API OAuth user once provisioned.
            c.CHANGEDBY                                                                                     AS CHANGEDBY
        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT c
        LEFT JOIN RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES a
            ON a.ID = c.PREFERRED_ADDRESS_ID
        LEFT JOIN (
            SELECT CONSTITUENTID, EMAILADDRESS
            FROM RAW.RAISERS_EDGE.VW_ODS_T_EMAILADDRESSES ea
            WHERE ea.TYPEDESCRIPTION IN (''Email'', ''Work Email'')
              AND ea.ISACTIVE = TRUE
              AND ea.EMAILADDRESS IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM RAW.RAISERS_EDGE.VW_ODS_T_EMAILADDRESSES excl
                  WHERE excl.CONSTITUENTID = ea.CONSTITUENTID
                    AND excl.EMAILADDRESS IS NOT NULL
                    AND LOWER(TRIM(excl.EMAILADDRESS)) = LOWER(TRIM(ea.EMAILADDRESS))
                    AND excl.TYPEDESCRIPTION IN (''Hard Bounce'', ''Hard Bounce 2'', ''Invalid Email'')
              )
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY ea.CONSTITUENTID
                ORDER BY
                    CASE ea.TYPEDESCRIPTION WHEN ''Email'' THEN 1 ELSE 2 END,
                    ea.ID DESC
            ) = 1
        ) e ON c.CONSTITUENT_ID = e.CONSTITUENTID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE ISPRIMARY = 1 AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ID ASC) = 1
        ) p ON c.CONSTITUENT_ID = p.CONSTITUENT_ID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE PHONETYPEDESCRIPTION = ''Home'' AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ISPRIMARY DESC, ID DESC) = 1
        ) hp ON c.CONSTITUENT_ID = hp.CONSTITUENT_ID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE PHONETYPEDESCRIPTION = ''Mobile'' AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ISPRIMARY DESC, ID DESC) = 1
        ) mp ON c.CONSTITUENT_ID = mp.CONSTITUENT_ID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE PHONETYPEDESCRIPTION = ''Work'' AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ISPRIMARY DESC, ID DESC) = 1
        ) wp ON c.CONSTITUENT_ID = wp.CONSTITUENT_ID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE PHONETYPEDESCRIPTION = ''Telephone'' AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ISPRIMARY DESC, ID DESC) = 1
        ) tel ON c.CONSTITUENT_ID = tel.CONSTITUENT_ID
        WHERE c.DECEASED = FALSE
    ) src
    ON tgt.SOURCE_SYSTEM = src.SOURCE_SYSTEM
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
    WHEN MATCHED --AND tgt.MD5 != src.MD5 --TODO: Removed MD5 check, address changes isnt included in MD5
    THEN UPDATE SET
        tgt.MD5              = src.MD5,
        tgt.SOURCE_DOMAIN    = src.SOURCE_DOMAIN,
        tgt.FULL_NAME        = src.FULL_NAME,
        tgt.FIRST_NAME       = src.FIRST_NAME,
        tgt.LAST_NAME        = src.LAST_NAME,
        tgt.EMAIL            = src.EMAIL,
        tgt.PHONE            = src.PHONE,
        tgt.ADDRESS_LINE1    = src.ADDRESS_LINE1,
        tgt.CITY             = src.CITY,
        tgt.POSTCODE         = src.POSTCODE,
        tgt.COUNTRY          = src.COUNTRY,
        tgt.COUNTRY_ISO2     = src.COUNTRY_ISO2,
        tgt.MIDDLE_NAME      = src.MIDDLE_NAME,
        tgt.TITLE            = src.TITLE,
        tgt.TITLE_2          = src.TITLE_2,
        tgt.SUFFIX           = src.SUFFIX,
        tgt.SUFFIX_2         = src.SUFFIX_2,
        tgt.GENDER           = src.GENDER,
        tgt.DATE_OF_BIRTH    = src.DATE_OF_BIRTH,
        tgt.DECEASED         = src.DECEASED,
        tgt.IS_MEMORIAL      = src.IS_MEMORIAL,
        tgt.DATE_DECEASED    = src.DATE_DECEASED,
        tgt.LOOKUP_ID        = src.LOOKUP_ID,
        tgt.ADDRESS_LINE2    = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3    = src.ADDRESS_LINE3,
        tgt.ADDRESS_LINE4    = src.ADDRESS_LINE4,
        tgt.COUNTY           = src.COUNTY,
        tgt.HOME_PHONE       = src.HOME_PHONE,
        tgt.MOBILE_PHONE     = src.MOBILE_PHONE,
        tgt.WORK_PHONE       = src.WORK_PHONE,
        tgt.TELEPHONE        = src.TELEPHONE,
        -- Echo suppression: when the writeback user is the last changer, preserve the
        -- existing LAST_UPDATED so the pipeline''s write never claims recency over a real
        -- human edit.  Replace ''RE_API_WRITEBACK'' with the actual writeback identity.
        tgt.LAST_UPDATED     = IFF(src.CHANGEDBY = ''RE_API_WRITEBACK'', tgt.LAST_UPDATED, src.LAST_UPDATED),
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP(),
        tgt._IS_ACTIVE       = TRUE
    WHEN NOT MATCHED THEN INSERT (
        MD5, STANDARDISED_ID, SOURCE_SYSTEM, SOURCE_RECORD_ID, SOURCE_DOMAIN,
        FULL_NAME, FIRST_NAME, LAST_NAME, EMAIL, PHONE,
        ADDRESS_LINE1, CITY, POSTCODE, COUNTRY, COUNTRY_ISO2,
        MIDDLE_NAME, TITLE, TITLE_2, SUFFIX, SUFFIX_2,
        GENDER, DATE_OF_BIRTH, DECEASED, IS_MEMORIAL, DATE_DECEASED, LOOKUP_ID,
        ADDRESS_LINE2, ADDRESS_LINE3, ADDRESS_LINE4, COUNTY,
        HOME_PHONE, MOBILE_PHONE, WORK_PHONE, TELEPHONE,
        LAST_UPDATED, _STANDARDISED_AT, _IS_ACTIVE
    ) VALUES (
        src.MD5, src.STANDARDISED_ID, src.SOURCE_SYSTEM, src.SOURCE_RECORD_ID, src.SOURCE_DOMAIN,
        src.FULL_NAME, src.FIRST_NAME, src.LAST_NAME, src.EMAIL, src.PHONE,
        src.ADDRESS_LINE1, src.CITY, src.POSTCODE, src.COUNTRY, src.COUNTRY_ISO2,
        src.MIDDLE_NAME, src.TITLE, src.TITLE_2, src.SUFFIX, src.SUFFIX_2,
        src.GENDER, src.DATE_OF_BIRTH, src.DECEASED, src.IS_MEMORIAL, src.DATE_DECEASED, src.LOOKUP_ID,
        src.ADDRESS_LINE2, src.ADDRESS_LINE3, src.ADDRESS_LINE4, src.COUNTY,
        src.HOME_PHONE, src.MOBILE_PHONE, src.WORK_PHONE, src.TELEPHONE,
        src.LAST_UPDATED, CURRENT_TIMESTAMP(), TRUE
    );
    rows_merged := SQLROWCOUNT;

    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS
    SET _IS_ACTIVE = FALSE, _STANDARDISED_AT = CURRENT_TIMESTAMP()
    WHERE SOURCE_SYSTEM = ''RAISERS_EDGE''
        AND _IS_ACTIVE = TRUE
        AND SOURCE_RECORD_ID NOT IN (
            SELECT CONSTITUENT_ID FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT
            WHERE DECEASED = FALSE
        );
    rows_deleted := SQLROWCOUNT;

    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.ALL_EMAILS       = src.ALL_EMAILS,
        tgt.ALL_PHONES       = src.ALL_PHONES,
        tgt.ALL_ADDRESSES    = src.ALL_ADDRESSES,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            c.CONSTITUENT_ID AS SOURCE_RECORD_ID,
            emails.ALL_EMAILS,
            phones.ALL_PHONES,
            addresses.ALL_ADDRESSES
        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT c
        LEFT JOIN (
            SELECT e.CONSTITUENTID,
                ARRAY_AGG(OBJECT_CONSTRUCT(
                    ''SOURCE_EMAIL_ID'', e.ID,
                    ''EMAIL'',           LOWER(TRIM(e.EMAILADDRESS)),
                    ''EMAIL_TYPE'',      e.TYPEDESCRIPTION,
                    ''IS_PRIMARY'',      e.ISPRIMARY,
                    ''IS_ACTIVE'',       e.ISACTIVE
                )) AS ALL_EMAILS
            FROM RAW.RAISERS_EDGE.VW_ODS_T_EMAILADDRESSES e
            WHERE e.EMAILADDRESS IS NOT NULL
            GROUP BY e.CONSTITUENTID
        ) emails ON c.CONSTITUENT_ID = emails.CONSTITUENTID
        LEFT JOIN (
            SELECT p.CONSTITUENT_ID,
                ARRAY_AGG(OBJECT_CONSTRUCT(
                    ''SOURCE_PHONE_ID'', p.ID,
                    ''PHONE'',           p.PHONENUMBER,
                    ''PHONE_TYPE'',      p.PHONETYPEDESCRIPTION,
                    ''IS_PRIMARY'',      p.ISPRIMARY,
                    ''IS_ACTIVE'',       p.ISACTIVE,
                    ''TPS_FLAG'',        p.TPSFLAG,
                    ''TPS_FLAG_DATE'',   p.TPSFLAGDATE
                )) AS ALL_PHONES
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS p
            WHERE p.PHONENUMBER IS NOT NULL AND TRIM(p.PHONENUMBER) != ''''
            GROUP BY p.CONSTITUENT_ID
        ) phones ON c.CONSTITUENT_ID = phones.CONSTITUENT_ID
        LEFT JOIN (
            SELECT ca.CONSTITUENT_ID,
                ARRAY_AGG(OBJECT_CONSTRUCT(
                    ''SOURCE_ADDRESS_ID'', a.ID,
                    ''ADDRESS_LINE1'',     a.ADDRESSLINE1,
                    ''ADDRESS_LINE2'',     a.ADDRESSLINE2,
                    ''ADDRESS_LINE3'',     a.ADDRESSLINE3,
                    ''CITY'',              a.CITY,
                    ''COUNTY'',            a.COUNTYDESCRIPTION,
                    ''POSTCODE'',          a.POSTCODE,
                    ''POSTCODE_VERIFIED'', a.POSTCODEVERIFIED,
                    ''COUNTRY'',           a.COUNTRYDESCRIPTION,
                    ''LATITUDE'',          a.LATITUDE,
                    ''LONGITUDE'',         a.LONGITUDE,
                    ''ADDRESS_TYPE'',      ca.ADDRESSTYPEDESCRIPTION,
                    ''IS_PREFERRED'',      ca.PREFERRED,
                    ''SEND_MAIL'',         ca.SENDMAIL,
                    ''VALID_FROM'',        ca.DATE_FROM,
                    ''VALID_TO'',          ca.DATE_TO
                )) AS ALL_ADDRESSES
            FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTADDRESSES ca
            INNER JOIN RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES a
                ON ca.ADDRESS_ID = a.ID
            GROUP BY ca.CONSTITUENT_ID
        ) addresses ON c.CONSTITUENT_ID = addresses.CONSTITUENT_ID
        WHERE c.DECEASED = FALSE
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''RAISERS_EDGE''
        AND tgt.SOURCE_RECORD_ID = src.SOURCE_RECORD_ID
        AND tgt._IS_ACTIVE = TRUE;
    rows_arrays := SQLROWCOUNT;

    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET tgt.FOUR_YEAR_RULE    = src.FOUR_YEAR_RULE,
        tgt._STANDARDISED_AT  = CURRENT_TIMESTAMP()
    FROM (
        WITH four_year_rule_cte AS (
            SELECT c.CONSTITUENT_ID,
                CASE WHEN
                    EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT c1
                        WHERE c1.CONSTITUENT_ID = c.CONSTITUENT_ID
                          AND TRY_TO_DATE(c1.DATEADDED) >= DATEADD(YEAR, -4, CURRENT_DATE())
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTTYPES ct
                        WHERE ct.CONSTITUENT_ID = c.CONSTITUENT_ID
                          AND ct.CONSTITUENTTYPEDESCRIPTION != ''Web User''
                          AND TRY_TO_DATE(ct.DATESTART) >= DATEADD(YEAR, -4, CURRENT_DATE())
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_GIFTS g
                        WHERE g.CONSTITUENT_ID = c.CONSTITUENT_ID
                          AND g.AMOUNT > 0
                          AND g.GIFTTYPEDESCRIPTION IN (''Cash'', ''Pledge Pay Cash'', ''Recurring Gift Pay Cash'')
                          AND TRY_TO_DATE(g.GIFTDATE) >= DATEADD(YEAR, -4, CURRENT_DATE())
                          AND NOT EXISTS (
                              SELECT 1
                              FROM RAW.RAISERS_EDGE.VW_ODS_T_SOFTCREDITS sc
                              WHERE sc.GIFTID = g.ID
                          )
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_TRIBUTES t
                        WHERE t.CONSTITUENTID = c.CONSTITUENT_ID
                          AND TRY_TO_DATE(t.DATEFROM) >= DATEADD(YEAR, -4, CURRENT_DATE())
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_PROPOSALS pr
                        JOIN RAW.RAISERS_EDGE.VW_ODS_T_PROSPECTS ps ON ps.ID = pr.PROSPECTID
                        WHERE ps.CONSTITUENT_ID = c.CONSTITUENT_ID
                          AND TRY_TO_DATE(pr.DATEASKED) >= DATEADD(YEAR, -4, CURRENT_DATE())
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_EVENTPARTICIPANTS ep
                        JOIN RAW.RAISERS_EDGE.VW_ODS_T_EVENTS ev ON ev.ID = ep.EVENTID
                        WHERE ep.CONSTITUENTID = c.CONSTITUENT_ID
                          AND TRY_TO_DATE(ev.STARTDATE) >= DATEADD(YEAR, -4, CURRENT_DATE())
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_MEMBERSHIP m
                        WHERE m.CONSTITUENTID = c.CONSTITUENT_ID
                          AND TRY_TO_DATE(m.DATESTART) >= DATEADD(YEAR, -4, CURRENT_DATE())
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES ca
                        WHERE ca.CONSTITUENT_ID = c.CONSTITUENT_ID
                          AND ca.ATTRIBUTENAME IN (
                              ''Autism Action Network Interests'',
                              ''Autism Action Network Issues'',
                              ''Autism Action Network Type'',
                              ''Benevolent Family Type'',
                              ''Community Enquiry'',
                              ''Community Participation'',
                              ''Event Clothing'',
                              ''Event Drop Out'',
                              ''Event Enquiry (OP)'',
                              ''Event Enquiry'',
                              ''Event Fundraiser Type'',
                              ''Event Participation'',
                              ''Event Rejection'',
                              ''Event Volunteer'',
                              ''Event Volunteer Drop Out'',
                              ''Event Volunteer Enquiry'',
                              ''Event Waiting List'',
                              ''Everyday Hero Registration ID'',
                              ''Fundraiser Website Page'',
                              ''Fundraising Website Source'',
                              ''Legacy Intender Source'',
                              ''Legacy Enquirer Source'',
                              ''Legacy Pledger Source'',
                              ''Payroll Giving Source'',
                              ''Professional - Age Group'',
                              ''Professional - Contact with Autism'',
                              ''Professional - Job Title'',
                              ''Professional - Work Sector'',
                              ''Purchaser Type'',
                              ''Source code'',
                              ''Subscriber Type'',
                              ''TogetherGifts Status'',
                              ''zGMM Event Enquiry'',
                              ''zGMM Event Participation''
                          )
                          AND TRY_TO_DATE(ca.ATTRIBUTEDATE) >= DATEADD(YEAR, -4, CURRENT_DATE())
                          AND NOT (ca.ATTRIBUTEVALUE = ''NAS e-newsletter'')
                          AND NOT (ca.ATTRIBUTEVALUE = ''Teacher Campaign'' AND ca.ATTRIBUTECOMMENT = ''Automatic Subscription for MyWorld'')
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_ACTIONS a
                        JOIN RAW.RAISERS_EDGE.VW_ODS_T_ACTIONNOTES an ON an.ACTIONID = a.ID
                        WHERE a.CONSTITUENTID = c.CONSTITUENT_ID
                          AND a.COMMUNICATIONTYPEDESCRIPTION IN (
                              ''Follow up to Enquiry'',
                              ''Helpline Call'',
                              ''Campaigns'',
                              ''Questionnaire/Survey'',
                              ''Campaigns Email'',
                              ''Campaigns Mailing'',
                              ''Update RE Record'',
                              ''Enquiry'',
                              ''Application''
                          )
                          AND a.STATUSDESCRIPTION IN (
                              ''Call made'',
                              ''Sent'',
                              ''Received'',
                              ''Action Taken''
                          )
                          AND (
                              an.ACTIONNOTEPADTYPEDESCRIPTION IN (
                                  ''Smart Survey Volunteer Audit Questionnaire'',
                                  ''TMI 2018 Call to Action Pledge'',
                                  ''Training and Consultancy Specification Webform'',
                                  ''update your details campaign -- webform completed -- record updated'',
                                  ''Conference Enquiry'',
                                  ''Adult Services Enquiry'',
                                  ''NAS Volunteer Enquiry Form'',
                                  ''Lorna Wing Centre Diagnosis Enquiry'',
                                  ''Autism Friendly Events -- Online Form'',
                                  ''Helpline Membership Mailing Request'',
                                  ''TMI Map Submission Message'',
                                  ''Engaging Networks'',
                                  ''Volunteer Application -- Arecruit'',
                                  ''Education Rights Query'',
                                  ''Transitions Support Service Query'',
                                  ''School Exclusions Service Query'',
                                  ''Volunteer Application -- Assemble -- hierarchy name'',
                                  ''NAS Webform - Campaigns enquirer form with soft opt-in'',
                                  ''Volunteer Application - Assemble - role title'',
                                  ''Autism accreditation enquiry form'',
                                  ''Autism Friendly Award Business Enquiry Form''
                              )
                              OR an.ACTIONNOTEPADTYPEDESCRIPTION LIKE ''%IG Permissions Campaign%''
                          )
                          AND TRY_TO_DATE(a.DATE) >= DATEADD(YEAR, -4, CURRENT_DATE())
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES ca
                        WHERE ca.CONSTITUENT_ID = c.CONSTITUENT_ID
                          AND ca.ATTRIBUTENAME IN (
                              ''Email Preferences'',
                              ''Postal Preferences'',
                              ''SMS Preferences'',
                              ''Telephone Preferences''
                          )
                          AND TRY_TO_DATE(ca.ATTRIBUTEDATE) >= DATEADD(YEAR, -4, CURRENT_DATE())
                    )
                THEN TRUE ELSE FALSE END AS FOUR_YEAR_RULE
            FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT c
            WHERE c.DECEASED = FALSE
        )
        SELECT * FROM four_year_rule_cte
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''RAISERS_EDGE''
      AND tgt.SOURCE_RECORD_ID = src.CONSTITUENT_ID
      AND tgt._IS_ACTIVE = TRUE
      AND tgt.FOUR_YEAR_RULE IS DISTINCT FROM src.FOUR_YEAR_RULE;
    rows_four_year_rule := SQLROWCOUNT;

    -- Attributes: LICENCED_USER_TYPE, PROFESSIONAL_WORK_SECTOR, JOB_TITLE, LEGACY_*
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.LICENCED_USER_TYPE       = src.LICENCED_USER_TYPE,
        tgt.PROFESSIONAL_WORK_SECTOR = src.PROFESSIONAL_WORK_SECTOR,
        tgt.JOB_TITLE                = src.JOB_TITLE,
        tgt.LEGACY_INTENDER          = src.LEGACY_INTENDER,
        tgt.LEGACY_PLEDGER           = src.LEGACY_PLEDGER,
        tgt.LEGACY_CONSIDERER        = src.LEGACY_CONSIDERER,
        tgt.LEGACY_ENQUIRER          = src.LEGACY_ENQUIRER,
        tgt._STANDARDISED_AT         = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            CONSTITUENT_ID,
            NULLIF(TRIM(MAX(CASE WHEN ATTRIBUTENAME = ''Licensed User Type''       THEN ATTRIBUTEVALUE END)), '''') AS LICENCED_USER_TYPE,
            NULLIF(LISTAGG(DISTINCT CASE WHEN ATTRIBUTENAME = ''Professional - Work Sector'' THEN ATTRIBUTEVALUE END, '';'')
                WITHIN GROUP (ORDER BY CASE WHEN ATTRIBUTENAME = ''Professional - Work Sector'' THEN ATTRIBUTEVALUE END), '''') AS PROFESSIONAL_WORK_SECTOR,
            NULLIF(TRIM(MAX(CASE WHEN ATTRIBUTENAME = ''Professional - Job Title'' THEN ATTRIBUTEVALUE END)), '''') AS JOB_TITLE,
            NULLIF(TRIM(MAX(CASE WHEN ATTRIBUTENAME = ''Legacy Intender''          THEN ATTRIBUTEVALUE END)), '''') AS LEGACY_INTENDER,
            NULLIF(TRIM(MAX(CASE WHEN ATTRIBUTENAME = ''Legacy Pledger''           THEN ATTRIBUTEVALUE END)), '''') AS LEGACY_PLEDGER,
            NULLIF(TRIM(MAX(CASE WHEN ATTRIBUTENAME = ''Legacy Considerer''        THEN ATTRIBUTEVALUE END)), '''') AS LEGACY_CONSIDERER,
            NULLIF(TRIM(MAX(CASE WHEN ATTRIBUTENAME = ''Legacy Enquirer''          THEN ATTRIBUTEVALUE END)), '''') AS LEGACY_ENQUIRER
        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTATTRIBUTES
        WHERE ATTRIBUTENAME IN (
            ''Licensed User Type'',
            ''Professional - Work Sector'',
            ''Professional - Job Title'',
            ''Legacy Intender'',
            ''Legacy Pledger'',
            ''Legacy Considerer'',
            ''Legacy Enquirer''
        )
        GROUP BY CONSTITUENT_ID
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''RAISERS_EDGE''
        AND tgt.SOURCE_RECORD_ID = src.CONSTITUENT_ID
        AND tgt._IS_ACTIVE = TRUE
        AND (
            tgt.LICENCED_USER_TYPE       IS DISTINCT FROM src.LICENCED_USER_TYPE
            OR tgt.PROFESSIONAL_WORK_SECTOR IS DISTINCT FROM src.PROFESSIONAL_WORK_SECTOR
            OR tgt.JOB_TITLE             IS DISTINCT FROM src.JOB_TITLE
            OR tgt.LEGACY_INTENDER       IS DISTINCT FROM src.LEGACY_INTENDER
            OR tgt.LEGACY_PLEDGER        IS DISTINCT FROM src.LEGACY_PLEDGER
            OR tgt.LEGACY_CONSIDERER     IS DISTINCT FROM src.LEGACY_CONSIDERER
            OR tgt.LEGACY_ENQUIRER       IS DISTINCT FROM src.LEGACY_ENQUIRER
        );
    rows_attributes := SQLROWCOUNT;

    -- Constituent type codes (boolean flags)
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
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
        tgt._STANDARDISED_AT            = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            CONSTITUENT_ID,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Major Donor''                AND DATEEND IS NULL, FALSE)) AS IS_MAJOR_DONOR,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Politician''                 AND DATEEND IS NULL, FALSE)) AS IS_POLITICIAN,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Celebrity''                  AND DATEEND IS NULL, FALSE)) AS IS_CELEBRITY,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''In Memory Donation Honouree'' AND DATEEND IS NULL
                AND TRY_TO_DATE(DATESTART) >= DATEADD(''year'', -2, CURRENT_DATE()), FALSE)) AS IN_MEMORY_DONATION_HONOUREE,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''In Memory Next of Kin''      AND DATEEND IS NULL
                AND TRY_TO_DATE(DATESTART) >= DATEADD(''year'', -2, CURRENT_DATE()), FALSE)) AS IN_MEMORY_NEXT_OF_KIN,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Benevolent Family''          AND DATEEND IS NULL, FALSE)) AS BENEVOLENT_FAMILY,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Corporate''                  AND DATEEND IS NULL, FALSE)) AS IS_CORPORATE,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''NAS Branch Contact''         AND DATEEND IS NULL, FALSE)) AS NAS_BRANCH_CONTACT,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''PR Case Study''              AND DATEEND IS NULL, FALSE)) AS PR_CASE_STUDY,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Statutory Authority''        AND DATEEND IS NULL, FALSE)) AS STATUTORY_AUTHORITY,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Special Eventer''            AND DATEEND IS NULL, FALSE)) AS SPECIAL_EVENTER,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Trusts''                     AND DATEEND IS NULL, FALSE)) AS TRUSTS,
            MAX(COALESCE(CONSTITUENTTYPEDESCRIPTION = ''Legacy Supporter''           AND DATEEND IS NULL, FALSE)) AS LEGACY_SUPPORTER
        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTTYPES
        GROUP BY CONSTITUENT_ID
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''RAISERS_EDGE''
        AND tgt.SOURCE_RECORD_ID = src.CONSTITUENT_ID
        AND tgt._IS_ACTIVE = TRUE
        AND (
            tgt.IS_MAJOR_DONOR              IS DISTINCT FROM src.IS_MAJOR_DONOR
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
        );
    rows_codes := SQLROWCOUNT;

    -- Solicit codes (semi-colon separated string)
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.SOLICIT_CODES    = src.SOLICIT_CODES,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            CONSTITUENTID AS CONSTITUENT_ID,
            LISTAGG(DISTINCT SOLICITCODEDESCRIPTION, '';'')
                WITHIN GROUP (ORDER BY SOLICITCODEDESCRIPTION) AS SOLICIT_CODES
        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTSOLICITCODES
        GROUP BY CONSTITUENTID
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''RAISERS_EDGE''
        AND tgt.SOURCE_RECORD_ID = src.CONSTITUENT_ID
        AND tgt._IS_ACTIVE = TRUE
        AND tgt.SOLICIT_CODES IS DISTINCT FROM src.SOLICIT_CODES;
    rows_solicit := SQLROWCOUNT;

    -- Backfill: identity, extended address, typed phones for records whose MD5 has not changed
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS tgt
    SET
        tgt.MIDDLE_NAME      = src.MIDDLE_NAME,
        tgt.TITLE            = src.TITLE,
        tgt.TITLE_2          = src.TITLE_2,
        tgt.SUFFIX           = src.SUFFIX,
        tgt.SUFFIX_2         = src.SUFFIX_2,
        tgt.GENDER           = src.GENDER,
        tgt.DATE_OF_BIRTH    = src.DATE_OF_BIRTH,
        tgt.DECEASED         = src.DECEASED,
        tgt.IS_MEMORIAL      = src.IS_MEMORIAL,
        tgt.DATE_DECEASED    = src.DATE_DECEASED,
        tgt.LOOKUP_ID        = src.LOOKUP_ID,
        tgt.ADDRESS_LINE2    = src.ADDRESS_LINE2,
        tgt.ADDRESS_LINE3    = src.ADDRESS_LINE3,
        tgt.ADDRESS_LINE4    = src.ADDRESS_LINE4,
        tgt.COUNTY           = src.COUNTY,
        tgt.HOME_PHONE       = src.HOME_PHONE,
        tgt.MOBILE_PHONE     = src.MOBILE_PHONE,
        tgt.WORK_PHONE       = src.WORK_PHONE,
        tgt.TELEPHONE        = src.TELEPHONE,
        tgt._STANDARDISED_AT = CURRENT_TIMESTAMP()
    FROM (
        SELECT
            c.CONSTITUENT_ID,
            INITCAP(NULLIF(TRIM(c.MIDDLE_NAME), ''''))    AS MIDDLE_NAME,
            NULLIF(TRIM(c.TITLE1), '''')                  AS TITLE,
            NULLIF(TRIM(c.TITLE2), '''')                  AS TITLE_2,
            NULLIF(TRIM(c.SUFFIX1), '''')                 AS SUFFIX,
            NULLIF(TRIM(c.SUFFIX2), '''')                 AS SUFFIX_2,
            c.GENDER                                    AS GENDER,
            c.DOB                                       AS DATE_OF_BIRTH,
            c.DECEASED::BOOLEAN                         AS DECEASED,
            c.ISHONOURMEMORIAL::BOOLEAN                 AS IS_MEMORIAL,
            c.DATEDECEASED                              AS DATE_DECEASED,
            NULLIF(TRIM(c.IMPORTID), '''')                AS LOOKUP_ID,
            INITCAP(TRIM(a.ADDRESSLINE2))                 AS ADDRESS_LINE2,
            INITCAP(TRIM(a.ADDRESSLINE3))                 AS ADDRESS_LINE3,
            INITCAP(TRIM(a.ADDRESSLINE4))                 AS ADDRESS_LINE4,
            INITCAP(TRIM(a.COUNTYDESCRIPTION))            AS COUNTY,
            hp.PHONENUMBER                              AS HOME_PHONE,
            mp.PHONENUMBER                              AS MOBILE_PHONE,
            wp.PHONENUMBER                              AS WORK_PHONE,
            tel.PHONENUMBER                             AS TELEPHONE
        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT c
        LEFT JOIN RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES a
            ON a.ID = c.PREFERRED_ADDRESS_ID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE PHONETYPEDESCRIPTION = ''Home'' AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ISPRIMARY DESC, ID DESC) = 1
        ) hp ON c.CONSTITUENT_ID = hp.CONSTITUENT_ID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE PHONETYPEDESCRIPTION = ''Mobile'' AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ISPRIMARY DESC, ID DESC) = 1
        ) mp ON c.CONSTITUENT_ID = mp.CONSTITUENT_ID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE PHONETYPEDESCRIPTION = ''Work'' AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ISPRIMARY DESC, ID DESC) = 1
        ) wp ON c.CONSTITUENT_ID = wp.CONSTITUENT_ID
        LEFT JOIN (
            SELECT CONSTITUENT_ID, PHONENUMBER
            FROM RAW.RAISERS_EDGE.VW_ODS_T_PHONENUMBERS
            WHERE PHONETYPEDESCRIPTION = ''Telephone'' AND ISACTIVE = 1
            QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENT_ID ORDER BY ISPRIMARY DESC, ID DESC) = 1
        ) tel ON c.CONSTITUENT_ID = tel.CONSTITUENT_ID
        WHERE c.DECEASED = FALSE
    ) src
    WHERE tgt.SOURCE_SYSTEM = ''RAISERS_EDGE''
        AND tgt.SOURCE_RECORD_ID = src.CONSTITUENT_ID
        AND tgt._IS_ACTIVE = TRUE
        AND (
            tgt.MIDDLE_NAME      IS DISTINCT FROM src.MIDDLE_NAME
            OR tgt.TITLE         IS DISTINCT FROM src.TITLE
            OR tgt.TITLE_2       IS DISTINCT FROM src.TITLE_2
            OR tgt.SUFFIX        IS DISTINCT FROM src.SUFFIX
            OR tgt.SUFFIX_2      IS DISTINCT FROM src.SUFFIX_2
            OR tgt.GENDER        IS DISTINCT FROM src.GENDER
            OR tgt.DATE_OF_BIRTH IS DISTINCT FROM src.DATE_OF_BIRTH
            OR tgt.DECEASED      IS DISTINCT FROM src.DECEASED
            OR tgt.IS_MEMORIAL   IS DISTINCT FROM src.IS_MEMORIAL
            OR tgt.DATE_DECEASED IS DISTINCT FROM src.DATE_DECEASED
            OR tgt.LOOKUP_ID     IS DISTINCT FROM src.LOOKUP_ID
            OR tgt.ADDRESS_LINE2 IS DISTINCT FROM src.ADDRESS_LINE2
            OR tgt.ADDRESS_LINE3 IS DISTINCT FROM src.ADDRESS_LINE3
            OR tgt.ADDRESS_LINE4 IS DISTINCT FROM src.ADDRESS_LINE4
            OR tgt.COUNTY        IS DISTINCT FROM src.COUNTY
            OR tgt.HOME_PHONE    IS DISTINCT FROM src.HOME_PHONE
            OR tgt.MOBILE_PHONE  IS DISTINCT FROM src.MOBILE_PHONE
            OR tgt.WORK_PHONE    IS DISTINCT FROM src.WORK_PHONE
            OR tgt.TELEPHONE     IS DISTINCT FROM src.TELEPHONE
        );
    rows_identity := SQLROWCOUNT;

    -- Normalisation pass: re-apply INITCAP to address fields on rows that were
    -- loaded before the UPPER->INITCAP change and whose source MD5 has not changed
    -- since (so the MERGE would not update them).  Runs only against rows where
    -- the stored value already differs from its INITCAP form.
    UPDATE MDM_DB.STAGING.STANDARDISED_RECORDS
    SET
        ADDRESS_LINE1 = INITCAP(TRIM(ADDRESS_LINE1)),
        ADDRESS_LINE2 = INITCAP(TRIM(ADDRESS_LINE2)),
        ADDRESS_LINE3 = INITCAP(TRIM(ADDRESS_LINE3)),
        ADDRESS_LINE4 = INITCAP(TRIM(ADDRESS_LINE4)),
        CITY          = INITCAP(TRIM(CITY)),
        COUNTY        = INITCAP(TRIM(COUNTY)),
        COUNTRY       = INITCAP(TRIM(COUNTRY))
    WHERE SOURCE_SYSTEM = ''RAISERS_EDGE''
        AND _IS_ACTIVE = TRUE
        AND (
            ADDRESS_LINE1 IS DISTINCT FROM INITCAP(TRIM(ADDRESS_LINE1))
            OR ADDRESS_LINE2 IS DISTINCT FROM INITCAP(TRIM(ADDRESS_LINE2))
            OR ADDRESS_LINE3 IS DISTINCT FROM INITCAP(TRIM(ADDRESS_LINE3))
            OR ADDRESS_LINE4 IS DISTINCT FROM INITCAP(TRIM(ADDRESS_LINE4))
            OR CITY IS DISTINCT FROM INITCAP(TRIM(CITY))
            OR COUNTY IS DISTINCT FROM INITCAP(TRIM(COUNTY))
            OR COUNTRY IS DISTINCT FROM INITCAP(TRIM(COUNTRY))
        );
    rows_normalise := SQLROWCOUNT;

    RETURN ''RE ETL complete. Merged: '' || rows_merged || '', Soft-deleted: '' || rows_deleted ||
           '', Arrays: '' || rows_arrays || '', Four-year rule: '' || rows_four_year_rule ||
           '', Attributes: '' || rows_attributes || '', Codes: '' || rows_codes ||
           '', Solicit: '' || rows_solicit || '', Identity backfill: '' || rows_identity ||
           '', Normalised: '' || rows_normalise;
END;
';