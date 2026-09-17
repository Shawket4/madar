# TillSpotCheck

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**approval_id** | Option<**uuid::Uuid**> |  | [optional]
**approved_by** | Option<**uuid::Uuid**> |  | [optional]
**approved_by_name** | Option<**String**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**cash_discrepancy** | **i64** | `counted_cash - expected_cash`. | 
**checked_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**checked_by** | **uuid::Uuid** |  | 
**checked_by_name** | **String** |  | 
**counted_cash** | **i64** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**expected_cash** | **i64** |  | 
**id** | **uuid::Uuid** |  | 
**methods** | [**Vec<models::SpotCheckMethodLine>**](SpotCheckMethodLine.md) |  | 
**note** | Option<**String**> |  | [optional]
**till_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


