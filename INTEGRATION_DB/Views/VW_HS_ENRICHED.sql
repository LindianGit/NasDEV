create or replace view INTEGRATION_DB.RAISERS_EDGE.VW_HS_ENRICHED(
	GOLDEN_RECORD_ID,
	CONSTITUENT_ID,
	IS_ORGANISATION,
	FIRST_NAME,
	SURNAME,
	FULL_NAME,
	MIDDLE_NAME,
	TITLE,
	TITLE_2,
	SUFFIX,
	SUFFIX_2,
	GENDER,
	DATE_OF_BIRTH,
	DECEASED,
	DATE_DECEASED,
	IS_MEMORIAL,
	ORGANISATION_NAME,
	LOOKUP_ID,
	ADDRESS_LINE_1,
	ADDRESS_LINE_2,
	ADDRESS_LINE_3,
	ADDRESS_LINE_4,
	CITY,
	COUNTY,
	POSTCODE,
	COUNTRY,
	PREFERRED_ADDRESS_ID,
	EMAIL,
	HOME_PHONE,
	MOBILE_PHONE,
	WORK_PHONE,
	WORK_EMAIL,
	TELEPHONE,
	SUBSCRIBER_TYPE,
	POSTAL_PREFERENCE,
	EMAIL_PREFERENCE,
	SMS_PREFERENCE,
	TELEPHONE_PREFERENCE,
	CONTACT_EXCLUSION,
	LICENCED_USER_TYPE,
	PROFESSIONAL_WORK_SECTOR,
	JOB_TITLE,
	LEGACY_INTENDER,
	LEGACY_PLEDGER,
	LEGACY_CONSIDERER,
	LEGACY_ENQUIRER,
	UK_COUNTRY,
	CONNECTION_TO_AUTISM,
	IS_MAJOR_DONOR,
	IS_POLITICIAN,
	IS_CELEBRITY,
	IN_MEMORY_DONATION_HONOUREE,
	IN_MEMORY_NEXT_OF_KIN,
	BENEVOLENT_FAMILY,
	IS_CORPORATE,
	NAS_BRANCH_CONTACT,
	PR_CASE_STUDY,
	STATUTORY_AUTHORITY,
	SPECIAL_EVENTER,
	TRUSTS,
	LEGACY_SUPPORTER,
	DO_NOT_CONTACT,
	SOLICIT_CODES,
	IN_MEMORY_DONOR,
	ACTIVE_REGULAR_GIVER,
	ACTIVE_PAYROLL_GIVER,
	CASH_GIVER,
	LOTTERY_PLAYER,
	CAMPAIGNER,
	VOLUNTEER_TYPE,
	VOLUNTEER_STATUS,
	FOUR_YEAR_RULE,
	LAST_UPDATED,
	_SOURCE_RANK
) as
WITH re_fallback AS (
    -- RE constituent ID for HS-sourced golden records that also have an RE XREF entry
    SELECT x.GOLDEN_RECORD_ID, x.SOURCE_RECORD_ID AS re_constituent_id
    FROM MDM_DB.GOLD.XREF x
    JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
        ON sr.SOURCE_SYSTEM = x.SOURCE_SYSTEM
        AND sr.SOURCE_RECORD_ID = x.SOURCE_RECORD_ID
        AND sr._IS_ACTIVE = TRUE
    WHERE x.SOURCE_SYSTEM = 'RAISERS_EDGE'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY x.GOLDEN_RECORD_ID
        ORDER BY sr.LAST_UPDATED DESC NULLS LAST
    ) = 1
),
hs_winner AS (
    SELECT
        x.GOLDEN_RECORD_ID,
        x.SOURCE_RECORD_ID          AS hs_source_id,
        x.STANDARDISED_ID,
        sr.LAST_UPDATED             AS last_updated
    FROM MDM_DB.GOLD.XREF x
    JOIN MDM_DB.STAGING.STANDARDISED_RECORDS sr
        ON sr.SOURCE_SYSTEM = x.SOURCE_SYSTEM
        AND sr.SOURCE_RECORD_ID = x.SOURCE_RECORD_ID
        AND sr._IS_ACTIVE = TRUE
    JOIN MDM_DB.GOLD.GOLDEN_RECORDS gr
        ON gr.GOLDEN_RECORD_ID = x.GOLDEN_RECORD_ID
        AND gr._IS_ACTIVE = TRUE
    WHERE x.SOURCE_SYSTEM = 'HUBSPOT'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY x.GOLDEN_RECORD_ID
        ORDER BY sr.LAST_UPDATED DESC NULLS LAST
    ) = 1
)

-- HS individual contacts
SELECT
    gr.GOLDEN_RECORD_ID                                         AS golden_record_id,
    COALESCE(
        TO_VARCHAR(con.PROPERTY_CONSTITUENT_ID::BIGINT),
        rf.re_constituent_id
    ) AS constituent_id,
    FALSE                                                       AS is_organisation,
    gr.FIRST_NAME                                               AS first_name,
    gr.LAST_NAME                                                AS surname,
    gr.FULL_NAME                                                AS full_name,
    NULL::VARCHAR                                               AS middle_name,
    con.PROPERTY_TITLE                                          AS title,
    NULL::VARCHAR                                               AS title_2,
    NULL::VARCHAR                                               AS suffix,
    NULL::VARCHAR                                               AS suffix_2,
    NULLIF(TRIM(con.PROPERTY_GENDER), '')                       AS gender, -- PROPERTY_GENDER_RE replaced by PROPERTY_GENDER
    con.PROPERTY_DATE_OF_BIRTH_FORM                             AS date_of_birth, -- PROPERTY_NAS_DATE_OF_BIRTH_ replaced by PROPERTY_DATE_OF_BIRTH_FORM
    TRY_CAST(con.PROPERTY_DECEASED AS BOOLEAN)                  AS deceased,
    NULL::VARCHAR                                               AS date_deceased,
    NULL::BOOLEAN                                               AS is_memorial,
    NULL::VARCHAR                                               AS organisation_name,
    NULL::VARCHAR                                               AS lookup_id,
    NULL::VARCHAR                                               AS address_line_1, -- PROPERTY_ADDRESS_LINE_1 removed from source
    con.PROPERTY_ADDRESS_LINE_2                                 AS address_line_2,
    con.PROPERTY_ADDRESS_LINE_3                                 AS address_line_3,
    con.PROPERTY_ADDRESS_LINE_4                                 AS address_line_4,
    con.PROPERTY_CITY                                           AS city,
    con.PROPERTY_ADDRESS_2_COUNTY                               AS county,
    con.PROPERTY_ZIP                                            AS postcode,
    con.PROPERTY_COUNTRY                                        AS country,
    NULL::NUMBER                                                AS preferred_address_id,
    gr.EMAIL                                                    AS email,
    con.PROPERTY_HOME_PHONE                                     AS home_phone,
    con.PROPERTY_MOBILEPHONE                                    AS mobile_phone,
    con.PROPERTY_BUSINESS_PHONE                                 AS work_phone,
    con.PROPERTY_WORK_EMAIL                                     AS work_email,
    NULL::VARCHAR                                               AS telephone,
    con.PROPERTY_SUBSCRIBER_TYPE                                AS subscriber_type,
    con.PROPERTY_POSTAL_PREFERENCE                              AS postal_preference,
    con.PROPERTY_EMAIL_PREFERENCE                               AS email_preference,
    con.PROPERTY_SMS_PREFERENCE                                 AS sms_preference,
    con.PROPERTY_TELEPHONE_PREFERENCE                           AS telephone_preference,
    con.PROPERTY_CONTACT_EXCLUSION                              AS contact_exclusion,
    con.PROPERTY_LICENSED_USER_TYPE                             AS licenced_user_type,
    con.PROPERTY_PROFESSIONAL_WORK_SECTOR                       AS professional_work_sector,
    con.PROPERTY_JOBTITLE                                       AS job_title,
    con.PROPERTY_LEGACY_INTENDER                                AS legacy_intender,
    con.PROPERTY_LEGACY_PLEDGER                                 AS legacy_pledger,
    con.PROPERTY_LEGACY_CONSIDERER                              AS legacy_considerer,
    NULLIF(TRIM(con.PROPERTY_LEGACY_PLEDGER_ENQUIRER), '')       AS legacy_enquirer, -- PROPERTY_LEGACY_ENQUIRER replaced by PROPERTY_LEGACY_PLEDGER_ENQUIRER
    con.PROPERTY_COUNTRY_UK                                     AS uk_country,
    NULLIF(TRIM(con.PROPERTY_WHAT_IS_YOUR_CONNECTION_TO_AUTISM), '') AS connection_to_autism, -- PROPERTY_CONNECTION_TO_AUTISM_NEW replaced by PROPERTY_WHAT_IS_YOUR_CONNECTION_TO_AUTISM
    TRY_CAST(con.PROPERTY_IS_A_MAJOR_DONOR AS BOOLEAN)          AS is_major_donor,
    TRY_CAST(con.PROPERTY_IS_A_POLITICIAN AS BOOLEAN)           AS is_politician,
    TRY_CAST(con.PROPERTY_CELEBRITY AS BOOLEAN)                 AS is_celebrity, -- PROPERTY_IS_A_CELEBRITY replaced by PROPERTY_CELEBRITY
    TRY_CAST(con.PROPERTY_IN_MEMORY_DONATION_HONOUREE AS BOOLEAN) AS in_memory_donation_honouree,
    TRY_CAST(con.PROPERTY_IN_MEMORY_NEXT_OF_KIN AS BOOLEAN)     AS in_memory_next_of_kin,
    TRY_CAST(con.PROPERTY_BENEVOLENT_FAMILY AS BOOLEAN)         AS benevolent_family,
    NULL::BOOLEAN                                               AS is_corporate, -- PROPERTY_IS_A_COPORATE removed from source
    TRY_CAST(con.PROPERTY_NAS_BRANCH_CONTACT AS BOOLEAN)        AS nas_branch_contact,
    TRY_CAST(con.PROPERTY_PR_CASE_STUDY AS BOOLEAN)             AS pr_case_study,
    TRY_CAST(con.PROPERTY_STATUTORY_AUTHORITY AS BOOLEAN)       AS statutory_authority,
    TRY_CAST(con.PROPERTY_SPECIAL_EVENTER AS BOOLEAN)           AS special_eventer,
    TRY_CAST(con.PROPERTY_TRUSTS AS BOOLEAN)                    AS trusts,
    TRY_CAST(con.PROPERTY_LEGACY_SUPPORTER AS BOOLEAN)          AS legacy_supporter,
    NULL::BOOLEAN                                               AS do_not_contact,
    con.PROPERTY_SOLICIT_CODES                                  AS solicit_codes,
    TRY_CAST(con.PROPERTY_IN_MEMORY_DONOR AS BOOLEAN)           AS in_memory_donor,
    TRY_CAST(con.PROPERTY_ACTIVE_REGULAR_GIVER AS BOOLEAN)      AS active_regular_giver,
    TRY_CAST(con.PROPERTY_ACTIVE_PAYROLL_GIVER AS BOOLEAN)      AS active_payroll_giver,
    TRY_CAST(con.PROPERTY_CASH_GIVER AS BOOLEAN)                AS cash_giver,
    TRY_CAST(con.PROPERTY_LOTTERY_PLAYER AS BOOLEAN)            AS lottery_player,
    TRY_CAST(con.PROPERTY_CAMPAIGNER AS BOOLEAN)                AS campaigner,
    con.PROPERTY_VOLUNTEER_TYPE                                 AS volunteer_type,
    con.PROPERTY_VOLUNTEER_STATUS                               AS volunteer_status,
    TRY_CAST(con.PROPERTY_N4_YEAR_RULE AS BOOLEAN)              AS four_year_rule,
    hw.last_updated                                             AS last_updated,
    2                                                           AS _source_rank
FROM MDM_DB.GOLD.GOLDEN_RECORDS gr
JOIN hs_winner hw ON hw.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
JOIN RAW.HUBSPOT.ODS_OBJECTS_CONTACTS con ON con.OBJECTID = hw.hs_source_id
LEFT JOIN re_fallback rf ON rf.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
WHERE hw.STANDARDISED_ID LIKE 'HS-%'
  AND TRY_CAST(con.PROPERTY_N4_YEAR_RULE AS BOOLEAN) = TRUE

UNION ALL

-- HS companies (organisations)
SELECT
    gr.GOLDEN_RECORD_ID                                             AS golden_record_id,
    COALESCE(
        TO_VARCHAR(comp.PROPERTY_CONSTITUENT_ID::BIGINT),
        rf.re_constituent_id
    ) AS constituent_id,
    TRUE                                                            AS is_organisation,
    gr.FIRST_NAME                                                   AS first_name,
    gr.LAST_NAME                                                    AS surname,
    gr.FULL_NAME                                                    AS full_name,
    NULL::VARCHAR                                                   AS middle_name,
    NULL::VARCHAR                                                   AS title,
    NULL::VARCHAR                                                   AS title_2,
    NULL::VARCHAR                                                   AS suffix,
    NULL::VARCHAR                                                   AS suffix_2,
    NULL::VARCHAR                                                   AS gender,
    NULL::VARCHAR                                                   AS date_of_birth,
    NULL::BOOLEAN                                                   AS deceased,
    NULL::VARCHAR                                                   AS date_deceased,
    NULL::BOOLEAN                                                   AS is_memorial,
    comp.PROPERTY_NAME                                              AS organisation_name,
    NULL::VARCHAR                                                   AS lookup_id,
    comp.PROPERTY_ADDRESS_LINE_1                                    AS address_line_1,
    comp.PROPERTY_ADDRESS_LINE_2                                    AS address_line_2,
    comp.PROPERTY_ADDRESS_LINE_3                                    AS address_line_3,
    comp.PROPERTY_ADDRESS_LINE_4                                    AS address_line_4,
    comp.PROPERTY_CITY                                              AS city,
    comp.PROPERTY_COUNTY                                            AS county,
    comp.PROPERTY_ZIP                                               AS postcode,
    comp.PROPERTY_COUNTRY                                           AS country,
    NULL::NUMBER                                                    AS preferred_address_id,
    gr.EMAIL                                                        AS email,
    NULL::VARCHAR                                                   AS home_phone,
    NULL::VARCHAR                                                   AS mobile_phone,
    NULL::VARCHAR                                                   AS work_phone,
    NULL::VARCHAR                                                   AS work_email,
    comp.PROPERTY_PHONE                                             AS telephone,
    comp.PROPERTY_SUBSCRIBER_TYPE                                   AS subscriber_type,
    NULL::VARCHAR                                                   AS postal_preference,
    comp.PROPERTY_EMAIL_PREFERENCE                                  AS email_preference,
    comp.PROPERTY_SMS_PREFERENCE                                    AS sms_preference,
    comp.PROPERTY_TELEPHONE_PREFERENCE                              AS telephone_preference,
    comp.PROPERTY_CONTACT_EXCLUSION                                 AS contact_exclusion,
    NULL::VARCHAR                                                   AS licenced_user_type,
    comp.PROPERTY_PROFESSIONAL__WORK_SECTOR                        AS professional_work_sector,
    comp.PROPERTY_PROFESSIONAL__JOB_TITLE                          AS job_title,
    comp.PROPERTY_LEGACY_INTENDER                                   AS legacy_intender,
    comp.PROPERTY_LEGACY_PLEDGER                                    AS legacy_pledger,
    comp.PROPERTY_LEGACY_CONSIDERER                                 AS legacy_considerer,
    comp.PROPERTY_LEGACY_ENQUIRER                                   AS legacy_enquirer,
    comp.PROPERTY_COUNTRY_UK                                        AS uk_country,
    comp.PROPERTY_CONNECTION_TO_AUTISM                              AS connection_to_autism,
    NULL::BOOLEAN                                                   AS is_major_donor,
    TRY_CAST(comp.PROPERTY_IS_A_POLITICIAN AS BOOLEAN)              AS is_politician,
    NULL::BOOLEAN                                                   AS is_celebrity,
    TRY_CAST(comp.PROPERTY_IN_MEMORY_DONATION_HONOUREE AS BOOLEAN)  AS in_memory_donation_honouree,
    TRY_CAST(comp.PROPERTY_IN_MEMORY_NEXT_OF_KIN AS BOOLEAN)        AS in_memory_next_of_kin,
    TRY_CAST(comp.PROPERTY_BENEVOLENT_FAMILY AS BOOLEAN)            AS benevolent_family,
    NULL::BOOLEAN                                                   AS is_corporate,
    TRY_CAST(comp.PROPERTY_NAS_BRANCH_CONTACT AS BOOLEAN)           AS nas_branch_contact,
    TRY_CAST(comp.PROPERTY_PR_CASE_STUDY AS BOOLEAN)                AS pr_case_study,
    TRY_CAST(comp.PROPERTY_STATUTORY_AUTHORITY AS BOOLEAN)          AS statutory_authority,
    TRY_CAST(comp.PROPERTY_SPECIAL_EVENTER AS BOOLEAN)              AS special_eventer,
    TRY_CAST(comp.PROPERTY_TRUSTS AS BOOLEAN)                       AS trusts,
    TRY_CAST(comp.PROPERTY_LEGACY_SUPPORTER AS BOOLEAN)             AS legacy_supporter,
    NULL::BOOLEAN                                                   AS do_not_contact,
    comp.PROPERTY_SOLICIT_CODES                                     AS solicit_codes,
    TRY_CAST(comp.PROPERTY_IN_MEMORY_DONOR AS BOOLEAN)              AS in_memory_donor,
    TRY_CAST(comp.PROPERTY_ACTIVE_REGULAR_GIVER AS BOOLEAN)         AS active_regular_giver,
    TRY_CAST(comp.PROPERTY_ACTIVE_PAYROLL_GIVER AS BOOLEAN)         AS active_payroll_giver,
    TRY_CAST(comp.PROPERTY_CASH_GIVER AS BOOLEAN)                   AS cash_giver,
    TRY_CAST(comp.PROPERTY_LOTTERY_PLAYER AS BOOLEAN)               AS lottery_player,
    TRY_CAST(comp.PROPERTY_CAMPAIGNER AS BOOLEAN)                   AS campaigner,
    comp.PROPERTY_VOLUNTEER_TYPE                                    AS volunteer_type,
    comp.PROPERTY_VOLUNTEER_STATUS                                  AS volunteer_status,
    TRY_CAST(comp.PROPERTY_N4_YEAR_RULE AS BOOLEAN)                 AS four_year_rule,
    hw.last_updated                                                 AS last_updated,
    2                                                               AS _source_rank
FROM MDM_DB.GOLD.GOLDEN_RECORDS gr
JOIN hs_winner hw ON hw.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
JOIN RAW.HUBSPOT.ODS_OBJECTS_COMPANIES comp ON comp.OBJECTID = hw.hs_source_id
LEFT JOIN re_fallback rf ON rf.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
WHERE hw.STANDARDISED_ID LIKE 'HSC-%'
  AND TRY_CAST(comp.PROPERTY_N4_YEAR_RULE AS BOOLEAN) = TRUE;