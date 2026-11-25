# Fundraising Page DEV Pilot

## Status

The local one-row request view is prepared, but it has not been run and no
Dynamics records have been written. This is a DEV-only pilot. Snowflake, ADF
and Dynamics must be operated by the user; no live-system access or pipeline
run was performed by the assistant.

## Proposed pilot scope

The local request view uses one Raiser’s Edge Event Participant Attribute
where:

- `CATEGORY = 'Fundraiser Website Page'`
- `VALUE` is a nonblank HTTP(S) URL no longer than 100 characters
- The URL host is recognized as `virginmoneygiving.com` (including subdomains)

The payload contains `mhnas_link` from `VALUE`, `mhnas_name` as
`VirginMoneyGiving.com` from the recognized URL host, and the fixed DEV pilot
GUID `39c3318a-77a7-4842-87ef-7cf07bef602a` in `mhnas_fundraisingpageid`.
Other hosts are held rather than guessed. The linked constituent had both
`VirginMoneyGiving.com` and `Realbuzz.com` source attributes, so the
constituent-level source does not identify the Platform for an individual
page. The Events section marks Event and Event Participant lookups as not
required for migration, so this pilot omits them. If Dynamics rejects the
request because a parent is required, stop and resolve the parent mapping
before retrying. Do not truncate long URLs or invent a Platform value.

The workbook also lists Proposal Attributes with category `Link` as a source
in the Community Events section. That route is not included in this pilot
until its relationship to the Event Participant route is clarified.

## Evidence and limits

- The workbook has different migration flags and sources for Fundraising Page
  under Events (rows 1023–1027) and Community Events (rows 3982–3986).
- Prior Snowflake profiling found 50,624 HTTP(S) participant-attribute values
  and 6,084 HTTP(S) proposal-attribute values. These are source rows, not
  confirmed distinct pages.
- Of those URL rows, 420 participant values and 109 proposal values exceeded
  the workbook’s 100-character Link limit. The limit has not been verified
  against live Dynamics metadata.
- The candidate participant attribute’s comment was `page 1 of 3`, not a
  Platform value. The constituent-level `Fundraising Website Source`
  attribute returned multiple values for that constituent; it is not
  page-specific.
- The supplied Dynamics metadata confirms the Fundraising Page fields and
  lookup navigation names, including Event Participant to
  `msnfp_eventpackage`. It does not confirm create-required fields or the live
  Link length limit.
- No local Fundraising Page request view or Event Participant-to-Dynamics
  Event Package migration view was found. A source-config entry for Dynamics
  Event Packages exists, but that is not proof of a usable parent mapping.
- The local request view selects the first eligible source attribute by RE
  attribute ID. Before dispatch, inspect the one-row view output and check
  that its URL does not already exist in Dynamics.

## Business questions

1. Are participant `Fundraiser Website Page` attributes and proposal `Link`
   attributes two separate page populations, or should one source take
   precedence?
2. Confirm URL-host mapping for each Platform and how redirects, custom hosts,
   and unrecognized domains should be handled. The pilot currently recognizes
   only the verified VirginMoneyGiving host; other hosts are held.
3. Can one participant or proposal have multiple pages? What defines a
   duplicate, and which value wins when the URL differs?
4. What should happen to blank, non-HTTP(S), malformed, or over-100-character
   URLs? Should long values be held for correction rather than truncated?
5. Which parent links should be populated (Event, Event Participant, or
   another record), and what should happen when a parent is missing?
6. Are historical pages in scope, or only pages considered active/current?
7. After initial creation, should changed URLs or Platform values update the
   existing Dynamics page?

## Gates before dispatch

1. The user reviews the one-row request in Snowflake DEV and confirms the
   source URL and recognized host-derived Platform value are appropriate.
2. Confirm that the candidate page does not already exist in Dynamics.
3. If the API reports a missing required parent, do not retry until its
   mapping and Dynamics ID are resolved.
4. The user publishes/runs the local dispatcher change in ADF DEV and supplies
   the Dynamics and XREF readback. Do not retry an uncertain POST until it has
   been reconciled.

This pilot tests the recognized VirginMoneyGiving host mapping only; it does
not approve mappings for other hosts or resolve the remaining business
questions. If the API rejects the GUID or any field, hold and revise the local
request before another run.
