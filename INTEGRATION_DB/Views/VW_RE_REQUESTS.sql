create or replace view INTEGRATION_DB.RAISERS_EDGE.VW_RE_REQUESTS(
	PIPELINE_ID,
	SOURCE_INSTANCE,
	ENTITY_ID,
	GOLDEN_RECORD_ID,
	CONSTITUENT_ID,
	SYSTEMRECORDID,
	HTTP_METHOD,
	REQUEST_URL,
	REQUEST_BODY,
	AUTH_METHOD,
	AUTH_CONFIG
) as

-- Constituent create / update
SELECT
    M.PIPELINE_ID,
    M.SOURCE_INSTANCE,
    M.ENTITY_ID,
    C.GOLDEN_RECORD_ID,
    C.CONSTITUENT_ID,
    C.SYSTEMRECORDID,
    C.ACTION AS HTTP_METHOD,
    CASE C.ACTION
        WHEN 'PATCH' THEN M.API_BASE_URL || '/constituents/' || C.SYSTEMRECORDID
        WHEN 'POST' THEN M.API_BASE_URL || '/constituents'
    END AS REQUEST_URL,
    C.PAYLOAD AS REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN INTEGRATION_DB.RAISERS_EDGE.VW_RE_CONSTITUENT AS C
LEFT JOIN INTEGRATION_DB.RAISERS_EDGE.VW_RE_ENRICHED AS RE_CURR
    ON C.GOLDEN_RECORD_ID = RE_CURR.GOLDEN_RECORD_ID
WHERE
    M.PIPELINE_ID = 'RE_WRITEBACK'
    AND M.ENTITY_ID = 'CONSTITUENT'
    AND M.ENABLED = TRUE
    AND (
        C.CONSTITUENT_ID IS NULL
        OR RE_CURR.GOLDEN_RECORD_ID IS NULL
        OR RE_CURR.IS_ORGANISATION = C.IS_ORGANISATION
    )
    AND (
        (
            C.CONSTITUENT_ID IS NULL
            AND (
                (
                    C.IS_ORGANISATION AND C.NAME IS NOT NULL
                    AND NOT EXISTS (
                        SELECT 1
                        FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT AS RE_ORG
                        WHERE
                            RE_ORG.ISORGANISATION = 1
                            AND LOWER(TRIM(REGEXP_REPLACE(
                                RE_ORG.ORGANISATIONNAME, '[[:space:]]+', ' '
                            )))
                            = LOWER(TRIM(REGEXP_REPLACE(
                                C.NAME, '[[:space:]]+', ' '
                            )))
                    )
                )
                OR (
                    NOT C.IS_ORGANISATION
                    AND C.LAST IS NOT NULL
                    AND C.LAST NOT LIKE '%@%'
                    AND (C.FIRST IS NULL OR C.FIRST NOT LIKE '%@%')
                    AND UPPER(TRIM(C.LAST)) NOT IN (
                        'UNKNOWN', 'TEST', 'ANONYMOUS', 'NONE', 'NULL', 'N/A'
                    )
                )
            )
        )
        OR (
            NOT C.IS_ORGANISATION
            AND RE_CURR.GOLDEN_RECORD_ID IS NOT NULL
            AND (
                (
                    NULLIF(C.FIRST, '') IS NOT NULL
                    AND LOWER(TRIM(REGEXP_REPLACE(C.FIRST, '[[:space:]]+', ' ')))
                    IS DISTINCT FROM LOWER(TRIM(REGEXP_REPLACE(RE_CURR.FIRST_NAME, '[[:space:]]+', ' ')))
                )
                OR (
                    NULLIF(C.LAST, '') IS NOT NULL
                    AND LOWER(TRIM(REGEXP_REPLACE(C.LAST, '[[:space:]]+', ' ')))
                    IS DISTINCT FROM LOWER(TRIM(REGEXP_REPLACE(RE_CURR.SURNAME, '[[:space:]]+', ' ')))
                )
                OR (
                    NULLIF(C.MIDDLE, '') IS NOT NULL
                    AND LOWER(TRIM(REGEXP_REPLACE(C.MIDDLE, '[[:space:]]+', ' ')))
                    IS DISTINCT FROM LOWER(TRIM(REGEXP_REPLACE(RE_CURR.MIDDLE_NAME, '[[:space:]]+', ' ')))
                )
                OR (
                    C.TITLE IS NOT NULL
                    AND C.TITLE IS DISTINCT FROM
                    CASE WHEN RE_CURR.TITLE IN ('Mr', 'Mrs', 'Ms', 'Miss', 'Mx', 'Dr') THEN RE_CURR.TITLE END
                )
                OR (
                    NULLIF(C.TITLE_2, '') IS NOT NULL
                    AND NULLIF(C.TITLE_2, '') IS DISTINCT FROM NULLIF(TRIM(RE_CURR.TITLE_2), '')
                )
                OR (
                    NULLIF(C.SUFFIX, '') IS NOT NULL
                    AND NULLIF(C.SUFFIX, '') IS DISTINCT FROM NULLIF(TRIM(RE_CURR.SUFFIX), '')
                )
                OR (
                    NULLIF(C.SUFFIX_2, '') IS NOT NULL
                    AND NULLIF(C.SUFFIX_2, '') IS DISTINCT FROM NULLIF(TRIM(RE_CURR.SUFFIX_2), '')
                )
                OR (
                    C.GENDER IS NOT NULL
                    AND C.GENDER IS DISTINCT FROM NULLIF(
                        CASE RE_CURR.GENDER
                            WHEN 'M' THEN 'Male'
                            WHEN 'F' THEN 'Female'
                            WHEN '?' THEN 'Unknown'
                        END, ''
                    )
                )
                OR (
                    C.DECEASED IS NOT NULL
                    AND C.DECEASED IS DISTINCT FROM RE_CURR.DECEASED
                )
                OR (
                    C.DECEASED_DATE IS NOT NULL
                    AND C.DECEASED_DATE IS DISTINCT FROM TRY_TO_DATE(RE_CURR.DATE_DECEASED)
                )
                OR (
                    C.IS_MEMORIAL IS NOT NULL
                    AND C.IS_MEMORIAL IS DISTINCT FROM RE_CURR.IS_MEMORIAL
                )
            )
            OR (
                C.IS_ORGANISATION
                AND RE_CURR.GOLDEN_RECORD_ID IS NOT NULL
                AND (
                    (
                        NULLIF(C.NAME, '') IS NOT NULL
                        AND LOWER(TRIM(REGEXP_REPLACE(C.NAME, '[[:space:]]+', ' ')))
                        IS DISTINCT FROM LOWER(TRIM(REGEXP_REPLACE(RE_CURR.ORGANISATION_NAME, '[[:space:]]+', ' ')))
                    )
                    OR (
                        C.IS_MEMORIAL IS NOT NULL
                        AND C.IS_MEMORIAL IS DISTINCT FROM RE_CURR.IS_MEMORIAL
                    )
                )
            )
        )
    )

UNION ALL

-- Preferred-address update
SELECT
    M.PIPELINE_ID,
    M.SOURCE_INSTANCE,
    M.ENTITY_ID,
    C.GOLDEN_RECORD_ID,
    C.CONSTITUENT_ID,
    C.SYSTEMRECORDID,
    'POST' AS HTTP_METHOD,
    M.API_BASE_URL || '/addresses' AS REQUEST_URL,
    OBJECT_CONSTRUCT(
        'address_lines', NULLIF(ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
            NULLIF(TRIM(C.ADDRESS_LINE_1), ''),
            NULLIF(TRIM(C.ADDRESS_LINE_2), ''),
            NULLIF(TRIM(C.ADDRESS_LINE_3), ''),
            NULLIF(TRIM(C.ADDRESS_LINE_4), '')
        ), CHR(10)), ''),
        'city', NULLIF(TRIM(C.CITY), ''),
        'county', NULLIF(TRIM(C.COUNTY), ''),
        'postal_code', LEFT(NULLIF(TRIM(C.POSTCODE), ''), 12),
        'country', NULLIF(TRIM(C.COUNTRY), ''),
        'preferred', TRUE,
        'constituent_id',NULLIF(TRIM(C.SYSTEMRECORDID),''),
        'type', NULLIF(TRIM(ADDRESSTYPEDESCRIPTION), '')
    ) AS REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN (
    SELECT
        VC.*,
        LOWER(ARRAY_TO_STRING(ARRAY_CAT(
            ARRAY_SORT(ARRAY_CONSTRUCT_COMPACT(
                NULLIF(TRIM(VC.ADDRESS_LINE_1), ''),
                NULLIF(TRIM(VC.ADDRESS_LINE_2), ''),
                NULLIF(TRIM(VC.ADDRESS_LINE_3), ''),
                NULLIF(TRIM(VC.ADDRESS_LINE_4), '')
            )),
            ARRAY_CONSTRUCT_COMPACT(
                NULLIF(TRIM(VC.CITY), ''),
                NULLIF(TRIM(VC.COUNTY), ''),
                LEFT(NULLIF(TRIM(VC.POSTCODE), ''), 12),
                NULLIF(TRIM(VC.COUNTRY), '')
            )
        ), ' ')) AS GOLDEN_ADDR_STR,
        LOWER(ARRAY_TO_STRING(ARRAY_CAT(
            ARRAY_SORT(ARRAY_CONSTRUCT_COMPACT(
                NULLIF(TRIM(RE_ADDR.ADDRESSLINE1), ''),
                NULLIF(TRIM(RE_ADDR.ADDRESSLINE2), ''),
                NULLIF(TRIM(RE_ADDR.ADDRESSLINE3), ''),
                NULLIF(TRIM(RE_ADDR.ADDRESSLINE4), '')
            )),
            ARRAY_CONSTRUCT_COMPACT(
                IFF(NULLIF(TRIM(VC.CITY), '') IS NOT NULL, NULLIF(TRIM(RE_ADDR.CITY), ''), NULL),
                IFF(NULLIF(TRIM(VC.COUNTY), '') IS NOT NULL, NULLIF(TRIM(RE_ADDR.COUNTYDESCRIPTION), ''), NULL),
                IFF(LEFT(NULLIF(TRIM(VC.POSTCODE), ''), 12) IS NOT NULL, LEFT(NULLIF(TRIM(RE_ADDR.POSTCODE), ''), 12), NULL),
                IFF(NULLIF(TRIM(VC.COUNTRY), '') IS NOT NULL, NULLIF(TRIM(RE_ADDR.COUNTRYDESCRIPTION), ''), NULL)
            )
        ), ' ')) AS RE_ADDR_STR,
        CA.ADDRESSTYPEDESCRIPTION AS ADDRESSTYPEDESCRIPTION
    FROM INTEGRATION_DB.RAISERS_EDGE.VW_RE_CONSTITUENT AS VC
    LEFT JOIN RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES AS RE_ADDR
        ON VC.PREFERRED_ADDRESS_ID = RE_ADDR.ID
    JOIN RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTADDRESSES CA ON CA.ID = RE_ADDR.ID
) AS C
WHERE
    M.PIPELINE_ID = 'RE_WRITEBACK'
    AND M.ENTITY_ID = 'ADDRESS'
    AND M.ENABLED = TRUE
    AND C.CONSTITUENT_ID IS NOT NULL
    AND C.SYSTEMRECORDID IS NOT NULL
    AND C.PREFERRED_ADDRESS_ID IS NOT NULL
    AND C.FOUR_YEAR = TRUE
    AND (
        NULLIF(C.GOLDEN_ADDR_STR, '') IS NOT NULL
        AND JAROWINKLER_SIMILARITY(C.GOLDEN_ADDR_STR, COALESCE(C.RE_ADDR_STR, '')) < 80
    )

UNION ALL

-- Email address writeback
SELECT
    M.PIPELINE_ID,
    M.SOURCE_INSTANCE,
    M.ENTITY_ID,
    E.GOLDEN_RECORD_ID,
    E.CONSTITUENT_ID,
    E.SYSTEMRECORDID,
    E.ACTION AS HTTP_METHOD,
    CASE E.ACTION
        WHEN 'PATCH' THEN M.API_BASE_URL || '/emailaddresses/' || E.EMAIL_ID::VARCHAR
        WHEN 'POST' THEN M.API_BASE_URL || '/emailaddresses'
    END AS REQUEST_URL,
    E.PAYLOAD AS REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN INTEGRATION_DB.RAISERS_EDGE.VW_RE_EMAILS AS E
WHERE
    M.PIPELINE_ID = 'RE_WRITEBACK'
    AND M.ENTITY_ID = 'EMAIL'
    AND M.ENABLED = TRUE

UNION ALL

-- Phone update
SELECT
    M.PIPELINE_ID,
    M.SOURCE_INSTANCE,
    M.ENTITY_ID,
    P.GOLDEN_RECORD_ID,
    P.CONSTITUENT_ID,
    P.SYSTEMRECORDID,
    P.ACTION AS HTTP_METHOD,
    M.API_BASE_URL || '/phones/' || P.PHONE_ID::VARCHAR AS REQUEST_URL,
    P.PAYLOAD AS REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN INTEGRATION_DB.RAISERS_EDGE.VW_RE_PHONES AS P
WHERE
    M.PIPELINE_ID = 'RE_WRITEBACK'
    AND M.ENTITY_ID = 'PHONE'
    AND M.ENABLED = TRUE

UNION ALL

-- New-phone create
SELECT
    M.PIPELINE_ID,
    M.SOURCE_INSTANCE,
    M.ENTITY_ID,
    PC.GOLDEN_RECORD_ID,
    PC.CONSTITUENT_ID,
    PC.SYSTEMRECORDID,
    'POST' AS HTTP_METHOD,
    M.API_BASE_URL || '/phonescollection' AS REQUEST_URL,
    OBJECT_CONSTRUCT(
        'constituent_id', PC.SYSTEMRECORDID,
        'phones', PC.PHONES
    ) AS REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN INTEGRATION_DB.RAISERS_EDGE.VW_RE_PHONE_COLLECTIONS AS PC
WHERE
    M.PIPELINE_ID = 'RE_WRITEBACK'
    AND M.ENTITY_ID = 'PHONE_COLLECTION'
    AND M.ENABLED = TRUE

UNION ALL

-- Do Not Contact writeback
SELECT
    M.PIPELINE_ID,
    M.SOURCE_INSTANCE,
    M.ENTITY_ID,
    SC.GOLDEN_RECORD_ID,
    SC.CONSTITUENT_ID,
    SC.SYSTEMRECORDID,
    SC.ACTION AS HTTP_METHOD,
    CASE SC.ACTION
        WHEN 'PATCH'
            THEN
                M.API_BASE_URL
                || '/communicationpreferences/'
                || SC.COMMUNICATION_PREFERENCE_ID::VARCHAR
        WHEN 'POST' THEN M.API_BASE_URL || '/communicationpreferences'
    END AS REQUEST_URL,
    SC.PAYLOAD AS REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN INTEGRATION_DB.RAISERS_EDGE.VW_RE_SOLICIT_CODES AS SC
WHERE
    M.PIPELINE_ID = 'RE_WRITEBACK'
    AND M.ENTITY_ID = 'SOLICIT_CODE'
    AND M.ENABLED = TRUE

UNION ALL

-- Custom field writeback
SELECT
    M.PIPELINE_ID,
    M.SOURCE_INSTANCE,
    M.ENTITY_ID,
    CF.GOLDEN_RECORD_ID,
    CF.CONSTITUENT_ID,
    CF.SYSTEMRECORDID,
    CF.ACTION AS HTTP_METHOD,
    CASE CF.ACTION
        WHEN 'PATCH'
            THEN
                M.API_BASE_URL
                || '/constituents/customfields/'
                || CF.CUSTOM_FIELD_ID
        WHEN 'POST' THEN M.API_BASE_URL || '/constituents/customfields'
    END AS REQUEST_URL,
    CF.PAYLOAD AS REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN INTEGRATION_DB.RAISERS_EDGE.VW_RE_CUSTOM_FIELDS_NEW AS CF
WHERE
    M.PIPELINE_ID = 'RE_WRITEBACK'
    AND M.ENTITY_ID = 'CUSTOM_FIELD'
    AND M.ENABLED = TRUE

UNION ALL

-- Constituent code writeback
SELECT
    M.PIPELINE_ID,
    M.SOURCE_INSTANCE,
    M.ENTITY_ID,
    CC.GOLDEN_RECORD_ID,
    CC.CONSTITUENT_ID,
    CC.SYSTEMRECORDID,
    CC.ACTION AS HTTP_METHOD,
    M.API_BASE_URL || '/constituentcodes' AS REQUEST_URL,
    CC.PAYLOAD AS REQUEST_BODY,
    M.AUTH_METHOD,
    M.AUTH_CONFIG
FROM AUDIT_DB.CONFIG.PIPELINE_METADATA AS M
CROSS JOIN INTEGRATION_DB.RAISERS_EDGE.VW_RE_CONSTITUENT_CODES AS CC
WHERE
    M.PIPELINE_ID = 'RE_WRITEBACK'
    AND M.ENTITY_ID = 'CONSTITUENT_CODE'
    AND M.ENABLED = TRUE;