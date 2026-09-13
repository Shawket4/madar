# TillBrief

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**device_code** | Option<**String**> |  | [optional]
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**device_label** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**opened_while_another_open** | **bool** |  | 
**status** | [**models::TillStatus**](TillStatus.md) |  | 
**teller_id** | **uuid::Uuid** |  | 
**teller_name** | **String** |  | 
**verification** | [**models::TillVerification**](TillVerification.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


