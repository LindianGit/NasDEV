create or replace dynamic table INTEGRATION_DB.DYNAMICS.DT_D365_ACCOUNT_PAYLOAD(
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
    A.GOLDEN_RECORD_ID,
    A.D365_ACCOUNT_ID AS TARGET_GUID,
    IFF(A.ACTION = 'CREATE', 'POST', 'PATCH') AS HTTP_METHOD,
    A.PAYLOAD,
    MD5(TO_VARCHAR(A.PAYLOAD)) AS PAYLOAD_MD5,
    (
        A.ACTION = 'CREATE'
        OR (
            A.ACTION = 'UPDATE'
            AND (
                -- No matching ODS row (deleted or never ingested) must
                -- not be swallowed as unchanged
                D.ACCOUNTID IS NULL
                -- Only fires when our side is non-NULL; a NULL on our
                -- side was never going to be sent
                OR (
                    A.NAME IS NOT NULL
                    AND A.NAME IS DISTINCT FROM D.NAME
                )
                OR (
                    A.MHA_SOURCEID IS NOT NULL
                    AND A.MHA_SOURCEID IS DISTINCT FROM D.MHA_SOURCEID
                )
                -- mha_source deliberately excluded: hardcoded literal
                OR (
                    A.ADDRESS1_LINE1 IS NOT NULL
                    AND A.ADDRESS1_LINE1 IS DISTINCT FROM D.ADDRESS1_LINE1
                )
                OR (
                    A.ADDRESS1_LINE2 IS NOT NULL
                    AND A.ADDRESS1_LINE2 IS DISTINCT FROM D.ADDRESS1_LINE2
                )
                OR (
                    A.ADDRESS1_LINE3 IS NOT NULL
                    AND A.ADDRESS1_LINE3 IS DISTINCT FROM D.ADDRESS1_LINE3
                )
                OR (
                    A.ADDRESS1_CITY IS NOT NULL
                    AND A.ADDRESS1_CITY IS DISTINCT FROM D.ADDRESS1_CITY
                )
                OR (
                    A.ADDRESS1_STATEORPROVINCE IS NOT NULL
                    AND A.ADDRESS1_STATEORPROVINCE
                    IS DISTINCT FROM D.ADDRESS1_STATEORPROVINCE
                )
                OR (
                    A.ADDRESS1_COUNTRY IS NOT NULL
                    AND A.ADDRESS1_COUNTRY IS DISTINCT FROM D.ADDRESS1_COUNTRY
                )
                OR (
                    A.ADDRESS1_POSTALCODE IS NOT NULL
                    AND A.ADDRESS1_POSTALCODE
                    IS DISTINCT FROM D.ADDRESS1_POSTALCODE
                )
                OR (
                    A.ADDRESS1_LATITUDE IS NOT NULL
                    AND A.ADDRESS1_LATITUDE IS DISTINCT FROM D.ADDRESS1_LATITUDE
                )
                OR (
                    A.ADDRESS1_LONGITUDE IS NOT NULL
                    AND A.ADDRESS1_LONGITUDE
                    IS DISTINCT FROM D.ADDRESS1_LONGITUDE
                )
                OR (
                    A.ADDRESS1_ADDRESSTYPECODE IS NOT NULL
                    AND A.ADDRESS1_ADDRESSTYPECODE
                    IS DISTINCT FROM D.ADDRESS1_ADDRESSTYPECODE
                )
                OR (
                    A.EMAILADDRESS1 IS NOT NULL
                    AND A.EMAILADDRESS1 IS DISTINCT FROM D.EMAILADDRESS1
                )
                OR (
                    A.EMAILADDRESS2 IS NOT NULL
                    AND A.EMAILADDRESS2 IS DISTINCT FROM D.EMAILADDRESS2
                )
                OR (
                    A.TELEPHONE1 IS NOT NULL
                    AND A.TELEPHONE1 IS DISTINCT FROM D.TELEPHONE1
                )
                OR (
                    A.TELEPHONE2 IS NOT NULL
                    AND A.TELEPHONE2 IS DISTINCT FROM D.TELEPHONE2
                )
                OR (
                    A.WEBSITEURL IS NOT NULL
                    AND A.WEBSITEURL IS DISTINCT FROM D.WEBSITEURL
                )
                OR (
                    A.INDUSTRYCODE IS NOT NULL
                    AND A.INDUSTRYCODE IS DISTINCT FROM D.INDUSTRYCODE
                )
                -- accountnumber, overriddencreatedon deliberately excluded:
                -- create-only, always NULL on update
            )
        )
    ) AS NEEDS_DISPATCH
FROM INTEGRATION_DB.DYNAMICS.VW_D365_ACCOUNT AS A
LEFT JOIN RAW.DYNAMICS.VW_ODS_ACCOUNTS AS D
    ON A.D365_ACCOUNT_ID = D.ACCOUNTID;
---rollback: DROP DYNAMIC TABLE IF EXISTS INTEGRATION_DB.DYNAMICS.DT_D365_ACCOUNT_PAYLOAD;
---verify: SELECT * FROM INTEGRATION_DB.DYNAMICS.DT_D365_ACCOUNT_PAYLOAD LIMIT 1;