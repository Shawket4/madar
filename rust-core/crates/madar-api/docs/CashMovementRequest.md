# CashMovementRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**client_ref** | Option<**uuid::Uuid**> |  | [optional]
**corrects_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**expense_advance_to** | Option<**uuid::Uuid**> | A pay-out handed to an employee for shop purchases: logged in Dawam as their expense advance, never deducted (AV-8). | [optional]
**kind** | Option<[**models::CashMovementKind**](CashMovementKind.md)> |  | [optional]
**note** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


