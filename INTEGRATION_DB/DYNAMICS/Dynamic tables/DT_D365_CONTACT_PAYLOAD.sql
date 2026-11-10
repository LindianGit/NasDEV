create or replace dynamic table INTEGRATION_DB.DYNAMICS.DT_D365_CONTACT_PAYLOAD(
	GOLDEN_RECORD_ID,
	TARGET_GUID,
	HTTP_METHOD,
	PAYLOAD,
	PAYLOAD_MD5,
	NEEDS_DISPATCH
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = WH_NAS_MDM_DEV
 as
-- NEEDS_DISPATCH: does Dynamics' current ODS value differ from what
-- we'd send. Computed here (once per hourly refresh) rather than live on
-- every dispatch call, for the same cost reason the payload itself is
-- materialised. See nas-snowflake/docs/integration/d365-payload-materialisation.md
-- for why this must stay ANDed with, not override, D365_WRITEBACK_STATE.
SELECT
    C.GOLDEN_RECORD_ID,
    C.D365_CONTACT_ID AS TARGET_GUID,
    IFF(C.ACTION = 'CREATE', 'POST', 'PATCH') AS HTTP_METHOD,
    C.PAYLOAD,
    MD5(TO_VARCHAR(C.PAYLOAD)) AS PAYLOAD_MD5,
    (
        C.ACTION = 'CREATE'
        OR (
            C.ACTION = 'UPDATE'
            AND (
                -- No matching ODS row (deleted or never ingested) must
                -- not be swallowed as unchanged
                D.CONTACTID IS NULL
                -- Only fires when our side is non-NULL; a NULL on our
                -- side was never going to be sent
                OR (
                    C.FIRSTNAME IS NOT NULL
                    AND C.FIRSTNAME IS DISTINCT FROM D.FIRSTNAME
                )
                OR (
                    C.LASTNAME IS NOT NULL
                    AND C.LASTNAME IS DISTINCT FROM D.LASTNAME
                )
                OR (
                    C.MIDDLENAME IS NOT NULL
                    AND C.MIDDLENAME IS DISTINCT FROM D.MIDDLENAME
                )
                OR (
                    C.MHA_SOURCEID IS NOT NULL
                    AND C.MHA_SOURCEID IS DISTINCT FROM D.MHA_SOURCEID
                )
                OR (
                    C.NAS_RECONSTITUENTCODE IS NOT NULL
                    AND C.NAS_RECONSTITUENTCODE
                    IS DISTINCT FROM D.NAS_RECONSTITUENTCODE
                )
                OR (
                    C.NAS_RESYSTEMRECORDID IS NOT NULL
                    AND C.NAS_RESYSTEMRECORDID
                    IS DISTINCT FROM D.NAS_RESYSTEMRECORDID
                )
                OR (
                    C.BIRTHDATE IS NOT NULL
                    AND C.BIRTHDATE IS DISTINCT FROM D.BIRTHDATE
                )
                OR (
                    C.MSNFP_DECEASED IS NOT NULL
                    AND C.MSNFP_DECEASED IS DISTINCT FROM D.MSNFP_DECEASED
                )
                OR (
                    C.GENDERCODE IS NOT NULL
                    AND C.GENDERCODE IS DISTINCT FROM D.GENDERCODE
                )
                -- mha_taxauthorityinvalid deliberately excluded: hardcoded
                -- TRUE, Gift Aid rewrites it Dynamics-side; diffing it would
                -- re-dispatch every contact for ever
                OR (
                    C.ADDRESS1_LINE1 IS NOT NULL
                    AND C.ADDRESS1_LINE1 IS DISTINCT FROM D.ADDRESS1_LINE1
                )
                OR (
                    C.ADDRESS1_LINE2 IS NOT NULL
                    AND C.ADDRESS1_LINE2 IS DISTINCT FROM D.ADDRESS1_LINE2
                )
                OR (
                    C.ADDRESS1_LINE3 IS NOT NULL
                    AND C.ADDRESS1_LINE3 IS DISTINCT FROM D.ADDRESS1_LINE3
                )
                OR (
                    C.ADDRESS1_CITY IS NOT NULL
                    AND C.ADDRESS1_CITY IS DISTINCT FROM D.ADDRESS1_CITY
                )
                OR (
                    C.ADDRESS1_STATEORPROVINCE IS NOT NULL
                    AND C.ADDRESS1_STATEORPROVINCE
                    IS DISTINCT FROM D.ADDRESS1_STATEORPROVINCE
                )
                OR (
                    C.ADDRESS1_COUNTRY IS NOT NULL
                    AND C.ADDRESS1_COUNTRY IS DISTINCT FROM D.ADDRESS1_COUNTRY
                )
                OR (
                    C.ADDRESS1_POSTALCODE IS NOT NULL
                    AND C.ADDRESS1_POSTALCODE
                    IS DISTINCT FROM D.ADDRESS1_POSTALCODE
                )
                OR (
                    C.ADDRESS1_LATITUDE IS NOT NULL
                    AND C.ADDRESS1_LATITUDE IS DISTINCT FROM D.ADDRESS1_LATITUDE
                )
                OR (
                    C.ADDRESS1_LONGITUDE IS NOT NULL
                    AND C.ADDRESS1_LONGITUDE
                    IS DISTINCT FROM D.ADDRESS1_LONGITUDE
                )
                OR (
                    C.ADDRESS1_UPSZONE IS NOT NULL
                    AND C.ADDRESS1_UPSZONE IS DISTINCT FROM D.ADDRESS1_UPSZONE
                )
                OR (
                    C.ADDRESS1_ADDRESSTYPECODE IS NOT NULL
                    AND C.ADDRESS1_ADDRESSTYPECODE
                    IS DISTINCT FROM D.ADDRESS1_ADDRESSTYPECODE
                )
                OR (
                    C.ADDRESS2_LINE1 IS NOT NULL
                    AND C.ADDRESS2_LINE1 IS DISTINCT FROM D.ADDRESS2_LINE1
                )
                OR (
                    C.ADDRESS2_LINE2 IS NOT NULL
                    AND C.ADDRESS2_LINE2 IS DISTINCT FROM D.ADDRESS2_LINE2
                )
                OR (
                    C.ADDRESS2_LINE3 IS NOT NULL
                    AND C.ADDRESS2_LINE3 IS DISTINCT FROM D.ADDRESS2_LINE3
                )
                OR (
                    C.ADDRESS2_CITY IS NOT NULL
                    AND C.ADDRESS2_CITY IS DISTINCT FROM D.ADDRESS2_CITY
                )
                OR (
                    C.ADDRESS2_STATEORPROVINCE IS NOT NULL
                    AND C.ADDRESS2_STATEORPROVINCE
                    IS DISTINCT FROM D.ADDRESS2_STATEORPROVINCE
                )
                OR (
                    C.ADDRESS2_COUNTRY IS NOT NULL
                    AND C.ADDRESS2_COUNTRY IS DISTINCT FROM D.ADDRESS2_COUNTRY
                )
                OR (
                    C.ADDRESS2_POSTALCODE IS NOT NULL
                    AND C.ADDRESS2_POSTALCODE
                    IS DISTINCT FROM D.ADDRESS2_POSTALCODE
                )
                OR (
                    C.ADDRESS2_LATITUDE IS NOT NULL
                    AND C.ADDRESS2_LATITUDE IS DISTINCT FROM D.ADDRESS2_LATITUDE
                )
                OR (
                    C.ADDRESS2_LONGITUDE IS NOT NULL
                    AND C.ADDRESS2_LONGITUDE
                    IS DISTINCT FROM D.ADDRESS2_LONGITUDE
                )
                OR (
                    C.ADDRESS2_UPSZONE IS NOT NULL
                    AND C.ADDRESS2_UPSZONE IS DISTINCT FROM D.ADDRESS2_UPSZONE
                )
                OR (
                    C.ADDRESS2_ADDRESSTYPECODE IS NOT NULL
                    AND C.ADDRESS2_ADDRESSTYPECODE
                    IS DISTINCT FROM D.ADDRESS2_ADDRESSTYPECODE
                )
                OR (
                    C.ADDRESS3_LINE1 IS NOT NULL
                    AND C.ADDRESS3_LINE1 IS DISTINCT FROM D.ADDRESS3_LINE1
                )
                OR (
                    C.ADDRESS3_LINE2 IS NOT NULL
                    AND C.ADDRESS3_LINE2 IS DISTINCT FROM D.ADDRESS3_LINE2
                )
                OR (
                    C.ADDRESS3_LINE3 IS NOT NULL
                    AND C.ADDRESS3_LINE3 IS DISTINCT FROM D.ADDRESS3_LINE3
                )
                OR (
                    C.ADDRESS3_CITY IS NOT NULL
                    AND C.ADDRESS3_CITY IS DISTINCT FROM D.ADDRESS3_CITY
                )
                OR (
                    C.ADDRESS3_STATEORPROVINCE IS NOT NULL
                    AND C.ADDRESS3_STATEORPROVINCE
                    IS DISTINCT FROM D.ADDRESS3_STATEORPROVINCE
                )
                OR (
                    C.ADDRESS3_COUNTRY IS NOT NULL
                    AND C.ADDRESS3_COUNTRY IS DISTINCT FROM D.ADDRESS3_COUNTRY
                )
                OR (
                    C.ADDRESS3_POSTALCODE IS NOT NULL
                    AND C.ADDRESS3_POSTALCODE
                    IS DISTINCT FROM D.ADDRESS3_POSTALCODE
                )
                OR (
                    C.ADDRESS3_LATITUDE IS NOT NULL
                    AND C.ADDRESS3_LATITUDE IS DISTINCT FROM D.ADDRESS3_LATITUDE
                )
                OR (
                    C.ADDRESS3_LONGITUDE IS NOT NULL
                    AND C.ADDRESS3_LONGITUDE
                    IS DISTINCT FROM D.ADDRESS3_LONGITUDE
                )
                OR (
                    C.ADDRESS3_UPSZONE IS NOT NULL
                    AND C.ADDRESS3_UPSZONE IS DISTINCT FROM D.ADDRESS3_UPSZONE
                )
                OR (
                    C.ADDRESS3_ADDRESSTYPECODE IS NOT NULL
                    AND C.ADDRESS3_ADDRESSTYPECODE
                    IS DISTINCT FROM D.ADDRESS3_ADDRESSTYPECODE
                )
                OR (
                    C.MSNFP_MAIDENNAME IS NOT NULL
                    AND C.MSNFP_MAIDENNAME IS DISTINCT FROM D.MSNFP_MAIDENNAME
                )
                OR (
                    C.NICKNAME IS NOT NULL
                    AND C.NICKNAME IS DISTINCT FROM D.NICKNAME
                )
                OR (
                    C.MSNFP_FACEBOOKPROFILE IS NOT NULL
                    AND C.MSNFP_FACEBOOKPROFILE
                    IS DISTINCT FROM D.MSNFP_FACEBOOKPROFILE
                )
                OR (
                    C.MSNFP_INSTAGRAMPROFILE IS NOT NULL
                    AND C.MSNFP_INSTAGRAMPROFILE
                    IS DISTINCT FROM D.MSNFP_INSTAGRAMPROFILE
                )
                OR (
                    C.MSNFP_LINKEDIN IS NOT NULL
                    AND C.MSNFP_LINKEDIN IS DISTINCT FROM D.MSNFP_LINKEDIN
                )
                OR (
                    C.MSNFP_TWITTER IS NOT NULL
                    AND C.MSNFP_TWITTER IS DISTINCT FROM D.MSNFP_TWITTER
                )
                -- lookups: compared against the ODS view's _*_VALUE read
                -- form, there is no same-named column on the ODS side
                OR (
                    C.MHA_TITLE IS NOT NULL
                    AND C.MHA_TITLE IS DISTINCT FROM D._MHA_TITLE_VALUE
                )
                OR (
                    C.MHA_ISOCOUNTRYID IS NOT NULL
                    AND C.MHA_ISOCOUNTRYID
                    IS DISTINCT FROM D._MHA_ISOCOUNTRYID_VALUE
                )
                OR (
                    C.NAS_COUNTRYID IS NOT NULL
                    AND C.NAS_COUNTRYID IS DISTINCT FROM D._NAS_COUNTRYID_VALUE
                )
                OR (
                    C.NAS_CONTACTTITLE IS NOT NULL
                    AND C.NAS_CONTACTTITLE IS DISTINCT FROM D.NAS_CONTACTTITLE
                )
                OR (
                    C.JOBTITLE IS NOT NULL
                    AND C.JOBTITLE IS DISTINCT FROM D.JOBTITLE
                )
                OR (
                    C.EMAILADDRESS1 IS NOT NULL
                    AND C.EMAILADDRESS1 IS DISTINCT FROM D.EMAILADDRESS1
                )
                OR (
                    C.EMAILADDRESS2 IS NOT NULL
                    AND C.EMAILADDRESS2 IS DISTINCT FROM D.EMAILADDRESS2
                )
                -- emailaddress3 deliberately excluded: always NULL, source
                -- unknown
                OR (
                    C.MOBILEPHONE IS NOT NULL
                    AND C.MOBILEPHONE IS DISTINCT FROM D.MOBILEPHONE
                )
                OR (
                    C.TELEPHONE1 IS NOT NULL
                    AND C.TELEPHONE1 IS DISTINCT FROM D.TELEPHONE1
                )
                OR (
                    C.TELEPHONE2 IS NOT NULL
                    AND C.TELEPHONE2 IS DISTINCT FROM D.TELEPHONE2
                )
                OR (
                    C.WEBSITEURL IS NOT NULL
                    AND C.WEBSITEURL IS DISTINCT FROM D.WEBSITEURL
                )
                -- msnfp_constituentnumber, overriddencreatedon deliberately
                -- excluded: create-only, always NULL on update
            )
        )
    ) AS NEEDS_DISPATCH
FROM INTEGRATION_DB.DYNAMICS.VW_D365_CONTACT AS C
LEFT JOIN RAW.DYNAMICS.VW_ODS_CONTACTS AS D
    ON C.D365_CONTACT_ID = D.CONTACTID;
---rollback: DROP DYNAMIC TABLE IF EXISTS INTEGRATION_DB.DYNAMICS.DT_D365_CONTACT_PAYLOAD;
---verify: SELECT * FROM INTEGRATION_DB.DYNAMICS.DT_D365_CONTACT_PAYLOAD LIMIT 1;