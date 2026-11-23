-- Read-only preview for the approved DEV Gift. This is not an outbox request.
-- The DateOnly fields are UserLocal in Dynamics; timezone behavior and final
-- write validation remain unresolved. The line's parent binding is added only
-- after the Transaction ID has been captured.
SELECT
    C.RE_GIFT_ID,
    C.RE_SPLIT_ID,
    OBJECT_CONSTRUCT(
        'transaction',
            OBJECT_CONSTRUCT(
                'mha_sourceid', TO_VARCHAR(C.RE_GIFT_ID),
                'msnfp_amount', C.GIFT_AMOUNT,
                'msnfp_bookdate', T.DRAFT_PAYLOAD:"msnfp_bookdate",
                'msnfp_depositdate', T.DRAFT_PAYLOAD:"msnfp_depositdate",
                'msnfp_posteddate', T.DRAFT_PAYLOAD:"msnfp_posteddate",
                'msnfp_CustomerId_' || C.DONOR_TYPE || '@odata.bind',
                    '/' || C.DONOR_TYPE || 's(' || C.DONOR_D365_ID || ')',
                'msnfp_OriginatingCampaignId@odata.bind',
                    C.DRAFT_ATTRIBUTION:"msnfp_OriginatingCampaignId@odata.bind",
                'msnfp_AppealId@odata.bind',
                    C.DRAFT_ATTRIBUTION:"msnfp_AppealId@odata.bind",
                'transactioncurrencyid@odata.bind',
                    '/transactioncurrencies(ef715fd1-e6fc-ec11-82e5-0022481b7c7b)',
                'mha_giftaidapplicable', FALSE,
                'mha_giftaideligible', FALSE
            ),
        'transaction_line_without_parent',
            OBJECT_CONSTRUCT(
                'msnfp_dataentryreference', TO_VARCHAR(C.RE_SPLIT_ID),
                'msnfp_amount', C.SPLIT_AMOUNT,
                'msnfp_designatiedcredit_designationId@odata.bind',
                    '/msnfp_designations(' || C.DESIGNATION_D365_ID || ')',
                'transactioncurrencyid@odata.bind',
                    '/transactioncurrencies(ef715fd1-e6fc-ec11-82e5-0022481b7c7b)',
                'mha_giftaidapplicable', FALSE,
                'mha_giftaideligible', FALSE
            ),
        'line_parent_binding_status', 'PENDING_TRANSACTION_ID_CAPTURE'
    ) AS DRAFT_PREVIEW
FROM INTEGRATION_DB.DYNAMICS.VW_D365_GIFT_PILOT_CANDIDATES_DEV AS C
INNER JOIN INTEGRATION_DB.DYNAMICS.VW_D365_MSNFP_TRANSACTION AS T
    ON C.RE_GIFT_ID = T.RE_GIFT_ID
WHERE C.RE_GIFT_ID = 50628
  AND C.RE_SPLIT_ID = 213112;
