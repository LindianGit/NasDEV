create or replace view INTEGRATION_DB.DYNAMICS.VW_D365_ACCOUNT(
	GOLDEN_RECORD_ID,
	ACTION,
	D365_ACCOUNT_ID,
	NAME,
	MHA_SOURCE,
	MHA_SOURCEID,
	ACCOUNTNUMBER,
	OVERRIDDENCREATEDON,
	ADDRESS1_LINE1,
	ADDRESS1_LINE2,
	ADDRESS1_LINE3,
	ADDRESS1_CITY,
	ADDRESS1_STATEORPROVINCE,
	ADDRESS1_COUNTRY,
	ADDRESS1_POSTALCODE,
	ADDRESS1_LATITUDE,
	ADDRESS1_LONGITUDE,
	ADDRESS1_ADDRESSTYPECODE,
	EMAILADDRESS1,
	EMAILADDRESS2,
	TELEPHONE1,
	TELEPHONE2,
	WEBSITEURL,
	INDUSTRYCODE,
	MSNFP_ACQUISITIONSOURCE,
	STATUSCODE,
	MHNAS_ADDRESS1NATION,
	PAYLOAD
) as
WITH WINNING_SOURCE_CTE AS (
    -- Most recently updated source per golden record, matches
    -- VW_HS_CONSTITUENT_ENRICHED's WINNING_SOURCE exactly (no secondary
    -- tiebreak)
    SELECT
        X.GOLDEN_RECORD_ID,
        X.SOURCE_SYSTEM,
        X.SOURCE_RECORD_ID,
        X.STANDARDISED_ID,
        ROW_NUMBER() OVER (
            PARTITION BY X.GOLDEN_RECORD_ID
            ORDER BY SR.LAST_UPDATED DESC NULLS LAST
        ) AS RN
    FROM MDM_DB.GOLD.XREF AS X
    INNER JOIN MDM_DB.STAGING.STANDARDISED_RECORDS AS SR
        ON
            X.SOURCE_SYSTEM = SR.SOURCE_SYSTEM
            AND X.SOURCE_RECORD_ID = SR.SOURCE_RECORD_ID
            AND SR._IS_ACTIVE = TRUE
    INNER JOIN MDM_DB.GOLD.GOLDEN_RECORDS AS GR
        ON
            X.GOLDEN_RECORD_ID = GR.GOLDEN_RECORD_ID
            AND GR._IS_ACTIVE = TRUE
),

-- Address1 = PREFERRED = -1 row (every constituent with an address has
-- exactly one, confirmed against live data), same rule as VW_D365_CONTACT;
-- no Account rows exist for Address2/3, so only one slot here
ADDRESS1_CTE AS (
    SELECT
        CA.CONSTITUENT_ID,
        CA.ADDRESSTYPEDESCRIPTION,
        A.LATITUDE,
        A.LONGITUDE
    FROM RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENTADDRESSES AS CA
    LEFT JOIN RAW.RAISERS_EDGE.VW_ODS_T_ADDRESSES AS A
        ON CA.ADDRESS_ID = A.ID
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY CA.CONSTITUENT_ID
            ORDER BY
                IFF(CA.PREFERRED = -1, 0, 1),
                CA.DATE_ADDED DESC,
                CA.ID DESC
        ) = 1
),

-- Email selection rule is unconfirmed
EMAIL2_CTE AS (
    SELECT
        CONSTITUENTID,
        EMAILADDRESS AS EMAIL2
    FROM RAW.RAISERS_EDGE.VW_ODS_T_EMAILADDRESSES
    WHERE TYPEDESCRIPTION = 'Work Email' AND ISACTIVE = 1
    QUALIFY
        ROW_NUMBER()
            OVER (PARTITION BY CONSTITUENTID ORDER BY ISPRIMARY DESC, ID DESC)
        = 1
),

-- WebSiteUrl: ODS_T_PHONENUMBERS truncates URLs at 20 chars, use
-- WEBADDRESSES.ADDRESS instead
WEBSITE_CTE AS (
    SELECT
        CONSTITUENTID,
        ADDRESS AS WEBSITE_URL
    FROM RAW.RAISERS_EDGE.VW_ODS_T_WEBADDRESSES
    WHERE TYPEDESCRIPTION = 'Website' AND ISACTIVE = 1
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CONSTITUENTID ORDER BY ID DESC) = 1
),

-- IndustryCode: RE-internal codes translated to text via
-- CODEDESCRIPTIONS, then to the Dynamics 1-33 Choice via the option-set
-- table; several RE descriptions don't map cleanly (expected, not a bug)
INDUSTRY_CTE AS (
    SELECT
        REL.CONSTITUENT_ID,
        CD.DESCRIPTION AS INDUSTRY_DESCRIPTION
    FROM RAW.RAISERS_EDGE.VW_ODS_T_RELATIONSHIPS AS REL
    LEFT JOIN RAW.RAISERS_EDGE.VW_ODS_T_CODEDESCRIPTIONS AS CD
        ON REL.INDUSTRY = CD.CODE AND CD.LOOKUPNAME = 'Industries'
    WHERE REL.INDUSTRY IS NOT NULL
    QUALIFY
        ROW_NUMBER()
            OVER (
                PARTITION BY REL.CONSTITUENT_ID
                ORDER BY REL.IS_PRIMARY DESC, REL.DATE_FROM DESC
            )
        = 1
)

SELECT
    GR.GOLDEN_RECORD_ID,

    -- Create/update decision: known D365 GUID means PATCH, else POST
    IFF(IDS.D365_ACCOUNT_ID IS NULL, 'CREATE', 'UPDATE') AS ACTION,
    IDS.D365_ACCOUNT_ID,

    NULLIF(GR.FULL_NAME, '') AS NAME,

    -- mha_Source hardcoded
    'Raiser''s Edge' AS MHA_SOURCE,
    RE_RAW.CONSTITUENT_ID AS MHA_SOURCEID,

    -- Alternate key: sent on create only, never on update -- live Dynamics
    -- accounts already use a non-RE 'ORG-XXXXX' native numbering format,
    -- and whether this field even accepts writes is still unconfirmed
    IFF(
        IDS.D365_ACCOUNT_ID IS NULL,
        RE_RAW.CONSTITUENT_ID,
        NULL
    ) AS ACCOUNTNUMBER,

    TRY_TO_TIMESTAMP_NTZ(RE_RAW.DATEADDED) AS OVERRIDDENCREATEDON,

    GR.ADDRESS_LINE1 AS ADDRESS1_LINE1,
    GR.ADDRESS_LINE2 AS ADDRESS1_LINE2,
    NULLIF(CONCAT_WS(', ', GR.ADDRESS_LINE3, GR.ADDRESS_LINE4), '')
        AS ADDRESS1_LINE3,
    GR.CITY AS ADDRESS1_CITY,
    GR.COUNTY AS ADDRESS1_STATEORPROVINCE,
    GR.COUNTRY AS ADDRESS1_COUNTRY,
    GR.POSTCODE AS ADDRESS1_POSTALCODE,
    A1.LATITUDE AS ADDRESS1_LATITUDE,
    A1.LONGITUDE AS ADDRESS1_LONGITUDE,
    -- AddressTypeCode: resolves NULL for most rows, same expected
    -- low hit rate as VW_D365_CONTACT
    OPT1.OPTION_VALUE AS ADDRESS1_ADDRESSTYPECODE,

    GR.EMAIL AS EMAILADDRESS1,
    E2.EMAIL2 AS EMAILADDRESS2,

    GR.WORK_PHONE AS TELEPHONE1,
    GR.HOME_PHONE AS TELEPHONE2,
    WEB.WEBSITE_URL AS WEBSITEURL,

    -- IndustryCode: near-zero hit rate expected except literal matches,
    -- no GOLDEN_RECORDS equivalent so fully gated on winning source
    OPT_IND.OPTION_VALUE AS INDUSTRYCODE,

    -- msnfp_AcquisitionSource: no working RE source found, resolves NULL
    NULL AS MSNFP_ACQUISITIONSOURCE,
    -- StatusCode: active/inactive criteria undefined
    NULL AS STATUSCODE,
    -- mhnas_Address1Nation: no working RE source found
    NULL AS MHNAS_ADDRESS1NATION,

    -- PAYLOAD: the Dataverse request body, built from the columns above
    -- (lateral alias reference) so it always matches what this view
    -- already exposes.
    OBJECT_CONSTRUCT(
        'name', NAME,
        'mha_source', MHA_SOURCE,
        'mha_sourceid', MHA_SOURCEID,
        -- create-only, double-guarded: redundant with ACCOUNTNUMBER's own
        -- column-level IFF above, deliberately -- do not simplify away
        'accountnumber',
        IFF(ACTION = 'CREATE', ACCOUNTNUMBER, NULL),
        -- create-only, double-guarded: redundant with OVERRIDDENCREATEDON's
        -- own column-level IFF above, deliberately -- do not simplify away
        'overriddencreatedon',
        IFF(ACTION = 'CREATE', OVERRIDDENCREATEDON, NULL),
        'address1_line1', ADDRESS1_LINE1,
        'address1_line2', ADDRESS1_LINE2,
        'address1_line3', ADDRESS1_LINE3,
        'address1_city', ADDRESS1_CITY,
        'address1_stateorprovince', ADDRESS1_STATEORPROVINCE,
        'address1_country', ADDRESS1_COUNTRY,
        'address1_postalcode', ADDRESS1_POSTALCODE,
        'address1_latitude', ADDRESS1_LATITUDE,
        'address1_longitude', ADDRESS1_LONGITUDE,
        'address1_addresstypecode', ADDRESS1_ADDRESSTYPECODE,
        'emailaddress1', EMAILADDRESS1,
        'emailaddress2', EMAILADDRESS2,
        'telephone1', TELEPHONE1,
        'telephone2', TELEPHONE2,
        'websiteurl', WEBSITEURL,
        'industrycode', INDUSTRYCODE,
        'msnfp_acquisitionsource', MSNFP_ACQUISITIONSOURCE,
        'statuscode', STATUSCODE,
        'mhnas_address1nation', MHNAS_ADDRESS1NATION
    ) AS PAYLOAD

FROM MDM_DB.GOLD.GOLDEN_RECORDS AS GR
INNER JOIN MDM_DB.GOLD.VW_GOLDEN_RECORD_IDS AS IDS
    ON GR.GOLDEN_RECORD_ID = IDS.GOLDEN_RECORD_ID
LEFT JOIN RAW.RAISERS_EDGE.VW_ODS_T_CONSTITUENT AS RE_RAW
    ON IDS.RE_CONSTITUENT_ID = RE_RAW.CONSTITUENT_ID
LEFT JOIN WINNING_SOURCE_CTE AS WS
    ON
        GR.GOLDEN_RECORD_ID = WS.GOLDEN_RECORD_ID
        AND WS.RN = 1
LEFT JOIN ADDRESS1_CTE AS A1
    ON
        RE_RAW.CONSTITUENT_ID = A1.CONSTITUENT_ID
        AND WS.SOURCE_SYSTEM = 'RAISERS_EDGE'
        AND WS.RN = 1
LEFT JOIN RAW.DYNAMICS.VW_ODS_OPTIONSET_ACCOUNT_ADDRESS1_ADDRESSTYPECODE AS OPT1
    ON TRIM(UPPER(A1.ADDRESSTYPEDESCRIPTION)) = TRIM(UPPER(OPT1.OPTION_LABEL))
LEFT JOIN EMAIL2_CTE AS E2
    ON
        RE_RAW.CONSTITUENT_ID = E2.CONSTITUENTID
        AND WS.SOURCE_SYSTEM = 'RAISERS_EDGE'
        AND WS.RN = 1
LEFT JOIN WEBSITE_CTE AS WEB
    ON
        RE_RAW.CONSTITUENT_ID = WEB.CONSTITUENTID
        AND WS.SOURCE_SYSTEM = 'RAISERS_EDGE'
        AND WS.RN = 1
LEFT JOIN INDUSTRY_CTE AS IC
    ON
        RE_RAW.CONSTITUENT_ID = IC.CONSTITUENT_ID
        AND WS.SOURCE_SYSTEM = 'RAISERS_EDGE'
        AND WS.RN = 1
LEFT JOIN RAW.DYNAMICS.VW_ODS_OPTIONSET_ACCOUNT_INDUSTRYCODE AS OPT_IND
    ON TRIM(UPPER(IC.INDUSTRY_DESCRIPTION)) = TRIM(UPPER(OPT_IND.OPTION_LABEL))
WHERE
    GR._IS_ACTIVE = TRUE
    AND GR.DOMAIN = 'ORGANISATION'
    AND IDS.IS_GDPR_SUPPRESSED = FALSE;