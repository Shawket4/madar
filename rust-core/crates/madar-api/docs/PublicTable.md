# PublicTable

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accepting** | **bool** | The branch is not serving right now — no till is open. The page says so instead of letting someone build a basket the kitchen will refuse. | 
**bill** | Option<[**models::PublicTableBill**](PublicTableBill.md)> | The meal in progress, when there is one. `None` means the table is free and this scan will start the bill. | [optional]
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**label** | **String** | What the table is called in the room — \"7\", \"T7\", \"Terrace 2\". | 
**org_id** | **uuid::Uuid** |  | 
**table_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


