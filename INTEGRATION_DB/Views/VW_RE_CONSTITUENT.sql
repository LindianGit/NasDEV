create or replace view INTEGRATION_DB.RAISERS_EDGE.VW_RE_CONSTITUENT(
	GOLDEN_RECORD_ID,
	CONSTITUENT_ID,
	SYSTEMRECORDID,
	IS_ORGANISATION,
	FIRST,
	LAST,
	MIDDLE,
	TITLE,
	TITLE_2,
	SUFFIX,
	SUFFIX_2,
	GENDER,
	BIRTHDATE,
	BIRTHDATE_D,
	BIRTHDATE_M,
	BIRTHDATE_Y,
	DECEASED,
	IS_MEMORIAL,
	DECEASED_DATE,
	DECEASED_DATE_D,
	DECEASED_DATE_M,
	DECEASED_DATE_Y,
	NAME,
	LOOKUP_ID,
	INACTIVE,
	ACTION,
	FOUR_YEAR,
	PREFERRED_ADDRESS_ID,
	ADDRESS_LINE_1,
	ADDRESS_LINE_2,
	ADDRESS_LINE_3,
	ADDRESS_LINE_4,
	CITY,
	COUNTY,
	POSTCODE,
	COUNTRY,
	PAYLOAD
) as
SELECT
    ids.GOLDEN_RECORD_ID,
    ids.RE_CONSTITUENT_ID                                         AS constituent_id,
    re_raw.SYSTEMRECORDID                                         AS systemrecordid,
    (gr.DOMAIN = 'ORGANISATION')                                  AS is_organisation,

    -- Individual fields (RE API ConstituentEdit)
    NULLIF(gr.FIRST_NAME, '')                                     AS first,
    NULLIF(gr.LAST_NAME, '')                                      AS last,
    NULLIF(gr.MIDDLE_NAME, '')                                    AS middle,
    CASE WHEN gr.DOMAIN != 'ORGANISATION'
              AND gr.TITLE IN ('Mr', 'Mrs', 'Ms', 'Miss', 'Mx', 'Dr')
         THEN gr.TITLE END                                        AS title,
    CASE WHEN gr.DOMAIN != 'ORGANISATION'
         THEN NULLIF(gr.TITLE_2, '') END                          AS title_2,
    CASE WHEN gr.DOMAIN != 'ORGANISATION'
         THEN NULLIF(gr.SUFFIX, '') END                           AS suffix,
    CASE WHEN gr.DOMAIN != 'ORGANISATION'
         THEN NULLIF(gr.SUFFIX_2, '') END                         AS suffix_2,
    CASE WHEN gr.DOMAIN != 'ORGANISATION' THEN
        CASE gr.GENDER
            WHEN 'M' THEN 'Male'
            WHEN 'F' THEN 'Female'
            WHEN '?' THEN 'Unknown'
            ELSE NULL
        END
    END                                                           AS gender,

    -- Birthdate as FuzzyDate parts
    CASE WHEN gr.DOMAIN != 'ORGANISATION'
         THEN TRY_TO_DATE(gr.DATE_OF_BIRTH) END                   AS birthdate,
    CASE WHEN gr.DOMAIN != 'ORGANISATION'
         THEN DAY(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT END          AS birthdate_d,
    CASE WHEN gr.DOMAIN != 'ORGANISATION'
         THEN MONTH(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT END        AS birthdate_m,
    CASE WHEN gr.DOMAIN != 'ORGANISATION'
         THEN YEAR(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT END         AS birthdate_y,

    gr.DECEASED                                                   AS deceased,
    gr.IS_MEMORIAL                                                AS is_memorial,

    -- Deceased date as FuzzyDate parts
    TRY_TO_DATE(gr.DATE_DECEASED)                                 AS deceased_date,
    DAY(TRY_TO_DATE(gr.DATE_DECEASED))::INT                       AS deceased_date_d,
    MONTH(TRY_TO_DATE(gr.DATE_DECEASED))::INT                     AS deceased_date_m,
    YEAR(TRY_TO_DATE(gr.DATE_DECEASED))::INT                      AS deceased_date_y,

    -- Organisation name
    CASE WHEN gr.DOMAIN = 'ORGANISATION'
         THEN NULLIF(gr.FULL_NAME, '') END                         AS name,

    NULLIF(gr.LOOKUP_ID, '')                                      AS lookup_id,
    FALSE                                                         AS inactive,

    IFF(ids.RE_CONSTITUENT_ID IS NULL, 'POST', 'PATCH')           AS action,

    gr.FOUR_YEAR                                                  AS four_year,

    re_raw.PREFERRED_ADDRESS_ID                                   AS preferred_address_id,
    gr.ADDRESS_LINE1                                              AS address_line_1,
    gr.ADDRESS_LINE2                                              AS address_line_2,
    gr.ADDRESS_LINE3                                              AS address_line_3,
    gr.ADDRESS_LINE4                                              AS address_line_4,
    gr.CITY                                                       AS city,
    gr.COUNTY                                                     AS county,
    gr.POSTCODE                                                   AS postcode,
    gr.COUNTRY                                                    AS country,

    CASE WHEN ids.RE_CONSTITUENT_ID IS NULL THEN
        IFF(
            gr.DOMAIN = 'ORGANISATION',
            OBJECT_CONSTRUCT(
                'type', 'Organization',
                'name', NULLIF(gr.FULL_NAME, ''),
                'inactive', FALSE,
                'is_memorial', gr.IS_MEMORIAL,
                'address', CASE
                    WHEN COALESCE(
                        NULLIF(TRIM(gr.ADDRESS_LINE1), ''),
                        NULLIF(TRIM(gr.CITY), ''),
                        NULLIF(TRIM(gr.POSTCODE), '')
                    ) IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'type', 'Home',
                        'address_lines', NULLIF(ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
                            NULLIF(TRIM(gr.ADDRESS_LINE1), ''),
                            NULLIF(TRIM(gr.ADDRESS_LINE2), ''),
                            NULLIF(TRIM(gr.ADDRESS_LINE3), ''),
                            NULLIF(TRIM(gr.ADDRESS_LINE4), '')
                        ), CHR(10)), ''),
                        'city', NULLIF(TRIM(gr.CITY), ''),
                        'county', NULLIF(TRIM(gr.COUNTY), ''),
                        'postal_code', LEFT(NULLIF(TRIM(gr.POSTCODE), ''), 12),
                        'country', NULLIF(TRIM(gr.COUNTRY), '')
                    )
                END,
                'email', CASE WHEN NULLIF(TRIM(gr.EMAIL), '') IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'address', NULLIF(TRIM(gr.EMAIL), ''),
                        'type', 'Email',
                        'primary', TRUE
                    )
                END,
                'phone', CASE WHEN NULLIF(TRIM(gr.TELEPHONE), '') IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'number', NULLIF(TRIM(gr.TELEPHONE), ''),
                        'type', 'Telephone',
                        'primary', TRUE
                    )
                END
            ),
            OBJECT_CONSTRUCT(
                'type', 'Individual',
                'first', NULLIF(gr.FIRST_NAME, ''),
                'last', NULLIF(gr.LAST_NAME, ''),
                'middle', NULLIF(gr.MIDDLE_NAME, ''),
                'title', CASE WHEN gr.TITLE IN ('Mr', 'Mrs', 'Ms', 'Miss', 'Mx', 'Dr')
                              THEN gr.TITLE END,
                'title_2', NULLIF(gr.TITLE_2, ''),
                'suffix', NULLIF(gr.SUFFIX, ''),
                'suffix_2', NULLIF(gr.SUFFIX_2, ''),
                'gender', CASE gr.GENDER
                    WHEN 'M' THEN 'Male'
                    WHEN 'F' THEN 'Female'
                    WHEN '?' THEN 'Unknown'
                    ELSE NULL
                END,
                'birthdate', CASE WHEN TRY_TO_DATE(gr.DATE_OF_BIRTH) IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'd', DAY(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT,
                        'm', MONTH(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT,
                        'y', YEAR(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT
                    )
                END,
                'deceased', gr.DECEASED,
                'deceased_date', CASE WHEN TRY_TO_DATE(gr.DATE_DECEASED) IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'd', DAY(TRY_TO_DATE(gr.DATE_DECEASED))::INT,
                        'm', MONTH(TRY_TO_DATE(gr.DATE_DECEASED))::INT,
                        'y', YEAR(TRY_TO_DATE(gr.DATE_DECEASED))::INT
                    )
                END,
                'inactive', FALSE,
                'is_memorial', gr.IS_MEMORIAL,
                'address', CASE
                    WHEN COALESCE(
                        NULLIF(TRIM(gr.ADDRESS_LINE1), ''),
                        NULLIF(TRIM(gr.CITY), ''),
                        NULLIF(TRIM(gr.POSTCODE), '')
                    ) IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'type', 'Home',
                        'address_lines', NULLIF(ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
                            NULLIF(TRIM(gr.ADDRESS_LINE1), ''),
                            NULLIF(TRIM(gr.ADDRESS_LINE2), ''),
                            NULLIF(TRIM(gr.ADDRESS_LINE3), ''),
                            NULLIF(TRIM(gr.ADDRESS_LINE4), '')
                        ), CHR(10)), ''),
                        'city', NULLIF(TRIM(gr.CITY), ''),
                        'county', NULLIF(TRIM(gr.COUNTY), ''),
                        'postal_code', LEFT(NULLIF(TRIM(gr.POSTCODE), ''), 12),
                        'country', NULLIF(TRIM(gr.COUNTRY), '')
                    )
                END,
                'email', CASE WHEN NULLIF(TRIM(gr.EMAIL), '') IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'address', NULLIF(TRIM(gr.EMAIL), ''),
                        'type', 'Email',
                        'primary', TRUE
                    )
                END,
                'phone', CASE
                    WHEN NULLIF(TRIM(gr.MOBILE_PHONE), '') IS NOT NULL
                        THEN OBJECT_CONSTRUCT(
                            'number', NULLIF(TRIM(gr.MOBILE_PHONE), ''),
                            'type', 'Mobile',
                            'primary', TRUE
                        )
                    WHEN NULLIF(TRIM(gr.HOME_PHONE), '') IS NOT NULL
                        THEN OBJECT_CONSTRUCT(
                            'number', NULLIF(TRIM(gr.HOME_PHONE), ''),
                            'type', 'Home',
                            'primary', TRUE
                        )
                    WHEN NULLIF(TRIM(gr.WORK_PHONE), '') IS NOT NULL
                        THEN OBJECT_CONSTRUCT(
                            'number', NULLIF(TRIM(gr.WORK_PHONE), ''),
                            'type', 'Work',
                            'primary', TRUE
                        )
                    WHEN NULLIF(TRIM(gr.TELEPHONE), '') IS NOT NULL
                        THEN OBJECT_CONSTRUCT(
                            'number', NULLIF(TRIM(gr.TELEPHONE), ''),
                            'type', 'Telephone',
                            'primary', TRUE
                        )
                END
            )
        )
    ELSE
        IFF(
            gr.DOMAIN = 'ORGANISATION',
            OBJECT_CONSTRUCT(
                'name', NULLIF(gr.FULL_NAME, ''),
                'inactive', FALSE,
                'is_memorial', gr.IS_MEMORIAL
            ),
            OBJECT_CONSTRUCT(
                'first', NULLIF(gr.FIRST_NAME, ''),
                'last', NULLIF(gr.LAST_NAME, ''),
                'middle', NULLIF(gr.MIDDLE_NAME, ''),
                'title', CASE WHEN gr.TITLE IN ('Mr', 'Mrs', 'Ms', 'Miss', 'Mx', 'Dr')
                              THEN gr.TITLE END,
                'title_2', NULLIF(gr.TITLE_2, ''),
                'suffix', NULLIF(gr.SUFFIX, ''),
                'suffix_2', NULLIF(gr.SUFFIX_2, ''),
                'gender', CASE gr.GENDER
                    WHEN 'M' THEN 'Male'
                    WHEN 'F' THEN 'Female'
                    WHEN '?' THEN 'Unknown'
                    ELSE NULL
                END,
                'birthdate', CASE WHEN TRY_TO_DATE(gr.DATE_OF_BIRTH) IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'd', DAY(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT,
                        'm', MONTH(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT,
                        'y', YEAR(TRY_TO_DATE(gr.DATE_OF_BIRTH))::INT
                    )
                END,
                'deceased', gr.DECEASED,
                'deceased_date', CASE WHEN TRY_TO_DATE(gr.DATE_DECEASED) IS NOT NULL
                    THEN OBJECT_CONSTRUCT(
                        'd', DAY(TRY_TO_DATE(gr.DATE_DECEASED))::INT,
                        'm', MONTH(TRY_TO_DATE(gr.DATE_DECEASED))::INT,
                        'y', YEAR(TRY_TO_DATE(gr.DATE_DECEASED))::INT
                    )
                END,
                'inactive', FALSE,
                'is_memorial', gr.IS_MEMORIAL
            )
        )
    END                                                           AS payload

FROM MDM_DB.GOLD.GOLDEN_RECORDS AS gr
INNER JOIN MDM_DB.GOLD.VW_GOLDEN_RECORD_IDS AS ids
    ON ids.GOLDEN_RECORD_ID = gr.GOLDEN_RECORD_ID
LEFT JOIN RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT AS re_raw
    ON re_raw.CONSTITUENT_ID = ids.RE_CONSTITUENT_ID AND re_raw.importid = gr.LOOKUP_ID
WHERE
    gr._IS_ACTIVE = TRUE
    AND ids.IS_GDPR_SUPPRESSED = FALSE;