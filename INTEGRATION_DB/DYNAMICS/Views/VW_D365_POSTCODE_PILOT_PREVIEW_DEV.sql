CREATE OR REPLACE VIEW INTEGRATION_DB.DYNAMICS.VW_D365_POSTCODE_PILOT_PREVIEW_DEV AS

-- Synthetic technical proof only: all 2,021,748 supplied RE address postcodes
-- were masked as ********. This marker is not a migrated postcode/classification.
SELECT
    'POSTCODE_TEST:DEV-001' AS TEST_KEY,
    'SYNTHETIC_ONLY' AS SOURCE_EVIDENCE,
    FALSE AS PREVIEW_DISPATCH_ALLOWED,
    OBJECT_CONSTRUCT(
        'mhnas_postcodeid', '6d60ded3-97a2-409a-bb8f-d62abb08315d',
        'mhnas_name', 'TEST-POSTCODE-DEV-001'
    ) AS DRAFT_PAYLOAD;
