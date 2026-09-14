# Till

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | Option<**String**> | Branch label (populated by reads; may be null on some write responses). | [optional]
**cash_discrepancy** | Option<**i32**> |  | [optional]
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**closed_by** | Option<**uuid::Uuid**> |  | [optional]
**closing_cash_declared** | Option<**i32**> |  | [optional]
**closing_cash_system** | Option<**i32**> |  | [optional]
**device_code** | Option<**String**> |  | [optional]
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**device_label** | Option<**String**> |  | [optional]
**disagreement_count** | **i64** |  | 
**flagged_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**force_close_reason** | Option<**String**> |  | [optional]
**force_closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**force_closed_by** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**notes** | Option<**String**> |  | [optional]
**old_bills_at_close** | Option<**i32**> |  | [optional]
**open_bills_at_close** | Option<**i32**> |  | [optional]
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**opened_while_another_open** | **bool** |  | 
**opening_cash** | **i32** |  | 
**opening_cash_edit_reason** | Option<**String**> |  | [optional]
**opening_cash_original** | Option<**i32**> |  | [optional]
**opening_cash_was_edited** | **bool** |  | 
**other_till_id** | Option<**uuid::Uuid**> |  | [optional]
**reconciliation_status** | Option<**String**> | `clean` | `disagreed` | `unreviewed` | null (open, or closed before reconciliation existed) | [optional]
**status** | [**models::TillStatus**](TillStatus.md) | `open` | `closed` | `force_closed` | 
**teller_id** | **uuid::Uuid** |  | 
**teller_name** | **String** |  | 
**timezone** | Option<**String**> |  | [optional]
**verification** | [**models::TillVerification**](TillVerification.md) | `server` | `lan` | `unverified` | `legacy` | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


