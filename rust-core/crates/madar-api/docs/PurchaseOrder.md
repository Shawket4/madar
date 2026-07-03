# PurchaseOrder

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | Option<**String**> | Branch label — populated by the order lists so the \"All branches\" view can show which branch each PO belongs to; other endpoints leave it null. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | **uuid::Uuid** |  | 
**expected_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**note** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**received_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**received_by** | Option<**uuid::Uuid**> |  | [optional]
**reference** | Option<**String**> |  | [optional]
**status** | **String** |  | 
**supplier_id** | Option<**uuid::Uuid**> |  | [optional]
**supplier_name** | Option<**String**> |  | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


