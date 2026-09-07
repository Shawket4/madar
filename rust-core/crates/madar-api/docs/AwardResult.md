# AwardResult

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**already_awarded** | **bool** | True when this order had already earned — a double tap, a retry, or a replayed offline op. Not an error: the outcome is the one that was asked for, and the response carries the balance that resulted. | 
**member** | [**models::MemberView**](MemberView.md) |  | 
**order_id** | **uuid::Uuid** |  | 
**points_awarded** | **i32** | Points this sale earned. 0 when it was too small to reach one point. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


