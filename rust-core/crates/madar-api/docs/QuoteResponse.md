# QuoteResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**distance_meters** | Option<**i32**> |  | [optional]
**fee** | Option<**i32**> |  | [optional]
**status** | **String** | \"ok\" | \"out_of_range\" | \"unavailable\" | 
**tax_policy** | [**models::OnlineTaxPolicy**](OnlineTaxPolicy.md) | The tax the cart will be priced under at this branch. A quote is a fee quote — it has no cart, so no tax amount — but the page rendering the checkout total needs the rate and the inclusivity beside the fee, or it shows the customer one number and intake records another. Present on every outcome: the policy is the branch's, not the address's. | 
**zone_id** | Option<**uuid::Uuid**> |  | [optional]
**zone_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


