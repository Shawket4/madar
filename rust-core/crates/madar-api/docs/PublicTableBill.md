# PublicTableBill

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** | When the party's bill was opened. The page counts up from this; a duration computed here would be wrong by the time it arrived. | 
**ready** | **bool** | The kitchen has finished everything fired so far. | 
**rounds** | [**Vec<models::PublicTableRound>**](PublicTableRound.md) | Every round fired, oldest first, with what went to the kitchen in each. | 
**subtotal** | **i32** | Lines as charged, before discount — the bill's first line, not the bill. | 
**ticket_id** | **uuid::Uuid** |  | 
**total** | **i32** | What the table will be asked to pay, as the SERVER prices it: the discount, the service charge and the tax are all in here, and none of them is something this page should be recomputing. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


