# TimeseriesPoint

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**discount** | **i64** |  | 
**orders** | **i64** |  | 
**period** | **String** |  | 
**refunded** | Option<**i64**> |  | [optional]
**revenue** | **i64** | Net of refunds against the period's sales; `refunded` is what came off. | 
**revenue_by_method** | Option<**serde_json::Value**> |  | 
**tax** | **i64** |  | 
**voided** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


