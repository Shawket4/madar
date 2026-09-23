# ProvisionOrgRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch** | [**models::ProvisionBranch**](ProvisionBranch.md) |  | 
**currency_code** | Option<**String**> |  | [optional]
**modules** | Option<**Vec<String>**> | `pos`, `dawam`; default both. A Dawam-only customer is `[\"dawam\"]` (SA-1). | [optional]
**name** | **String** |  | 
**owner** | [**models::ProvisionOwner**](ProvisionOwner.md) |  | 
**slug** | **String** |  | 
**tax_rate** | Option<**f64**> | A FRACTION (0.14 = 14%). Default 0 (locked decision). | [optional]
**template** | **String** | `restaurant` or `cafe`. | 
**timezone** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


