# LookupRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_id** | Option<**uuid::Uuid**> | A member the till already identified, re-read before a charge so the balance and catalogue it prices against are the server's current ones. | [optional]
**phone** | Option<**String**> | Manual fallback for a customer whose phone is dead. | [optional]
**token** | Option<**String**> | The token from the scanned pass barcode. Preferred. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


