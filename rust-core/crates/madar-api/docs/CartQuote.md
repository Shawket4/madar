# CartQuote

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**deal_discount** | **i32** | Σ deals' discount. | 
**deals** | [**Vec<models::QuotedDeal>**](QuotedDeal.md) |  | 
**items_total** | **i32** | Σ line_total, before deals. | 
**lines** | [**Vec<models::QuotedLine>**](QuotedLine.md) |  | 
**total_after_deals** | **i32** | `items_total − deal_discount` (before the channel discount, tax and fees). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


