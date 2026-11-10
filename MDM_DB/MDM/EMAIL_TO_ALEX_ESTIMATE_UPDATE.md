**Subject:** Update to my estimate: mapping workbook findings

Hi Alex,

My first figure of 15–32 days was an early view based on the Snowflake code and the architecture, before I'd worked through the mapping workbook. It assumed the mapping was complete, as discussed.

Having now analysed the workbook in detail, about 44% of the fields marked required for migration (roughly 200 of 463) don't yet have a source defined, and business rules are written for only a small number. The cut-off criteria and gift-splitting rules are also still open. That is extra work that wasn't visible earlier, so I now expect a range of about 45–80 days, depending on whether those gaps are closed first.

I can send a gap report by entity so you can check the figures, and walk you through it whenever suits.

Kind regards,
Lindian

---
Draft note: ADF already lands 72 Raisers Edge tables, about 40 of which no code reads. Some of the "no source" fields may be covered by them, so the gap figure could fall once the mapping's table names are matched. Consider saying so, or send after that check. Also confirm the 463 / 204 counts in Excel and that "required" matches how NAS uses the flag before sending.
