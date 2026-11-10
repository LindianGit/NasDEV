CREATE OR REPLACE PROCEDURE MDM_DB.STAGING.SP_STANDARDISE_RECORDS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET re_result VARCHAR := '''';
    LET hs_result VARCHAR := '''';
    LET dyn_result VARCHAR := ''skipped (disabled, see docs/known-issues/mdm-exact-org-name-no-postcode-check.md)'';
    CALL MDM_DB.STAGING.SP_ETL_RAISERS_EDGE() INTO :re_result;
    CALL MDM_DB.STAGING.SP_ETL_HUBSPOT() INTO :hs_result;
    -- CALL MDM_DB.STAGING.SP_ETL_DYNAMICS() INTO :dyn_result; -- disabled until known-issue fixed and validated in TEST
    RETURN ''Raisers Edge: '' || re_result || '' | HubSpot: '' || hs_result || '' | Dynamics: '' || dyn_result;
END;
';