# Shift

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | Option<**String**> | Branch label — only populated by the shifts list (so the \"All branches\" view can show which branch each shift belongs to). Other shift endpoints leave it `null`. | [optional]
**cash_discrepancy** | Option<**i32**> |  | [optional]
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**closed_by** | Option<**uuid::Uuid**> |  | [optional]
**closing_cash_declared** | Option<**i32**> |  | [optional]
**closing_cash_system** | Option<**i32**> |  | [optional]
**force_close_reason** | Option<**String**> |  | [optional]
**force_closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**force_closed_by** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**notes** | Option<**String**> |  | [optional]
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**opening_cash** | **i32** |  | 
**opening_cash_edit_reason** | Option<**String**> |  | [optional]
**opening_cash_original** | Option<**i32**> |  | [optional]
**opening_cash_was_edited** | **bool** |  | 
**status** | **String** |  | 
**teller_id** | **uuid::Uuid** |  | 
**teller_name** | **String** |  | 
**till_id** | Option<**uuid::Uuid**> | The till (drawer) this shift is on. Populated by the read/list/open endpoints; mutation responses that build the row via RETURNING may leave `till_name` null (same convention as `branch_name`). | [optional]
**till_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


