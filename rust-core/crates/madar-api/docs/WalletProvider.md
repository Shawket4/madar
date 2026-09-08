# WalletProvider

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**configured** | **bool** | Everything present. False means the button is not offered at all. | 
**detail** | Option<**String**> |  | [optional]
**missing** | **Vec<String>** | The settings still missing, by name. Empty when `configured`. | 
**reachable** | Option<**bool**> | Google only: what Google itself said when asked. `None` for Apple, which signs locally and has nobody to ask. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


