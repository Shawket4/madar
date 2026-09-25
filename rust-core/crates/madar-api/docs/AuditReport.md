# AuditReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**by_issuer** | [**Vec<models::AuditBreakdownEntry>**](AuditBreakdownEntry.md) |  | 
**by_kind** | Option<[**Vec<models::AuditBreakdownEntry>**](AuditBreakdownEntry.md)> | Discounts audit only: by act (`preset` / `manual_amount` / `manual_percent`; `unattributed` for sales from before). Additive. | [optional]
**by_reason** | [**Vec<models::AuditBreakdownEntry>**](AuditBreakdownEntry.md) |  | 
**entries** | Option<[**Vec<models::DiscountAuditEntry>**](DiscountAuditEntry.md)> | Discounts audit only: the most recent discounted sales, newest first (at most 200). Additive. | [optional]
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**history** | Option<[**Vec<models::DeductionOverrideEvent>**](DeductionOverrideEvent.md)> | Deduction overrides audit only: every waive, unwaive and override event with who, when and why, newest first (at most 500) — the history, so a waiver later undone still shows (owner decision D8, AT-10). Additive. | [optional]
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**total_amount_minor** | **i64** |  | 
**total_count** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


