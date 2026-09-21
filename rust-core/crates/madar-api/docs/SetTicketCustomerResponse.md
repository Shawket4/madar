# SetTicketCustomerResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**applied** | **bool** | False when nothing was written: unknown customer, unknown or voided bill. | 
**customer_id** | Option<**uuid::Uuid**> | What the bill now says, after the merge chain: the survivor of a merged id, `null` when the customer was taken off, and the PREVIOUS value when the id was unknown (the pick is dropped, the bill is untouched). | [optional]
**order_id** | Option<**uuid::Uuid**> | The sale the change landed on instead, when the bill was already settled by the time this arrived. | [optional]
**ticket_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


