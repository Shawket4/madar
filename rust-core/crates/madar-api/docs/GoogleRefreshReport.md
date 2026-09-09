# GoogleRefreshReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**class** | Option<**serde_json::Value**> | The class as Google holds it now. | [optional]
**class_locations** | **u32** | Branches Google kept on the shop's class. | 
**error** | Option<**String**> | The first thing that went wrong, if anything did. | [optional]
**object** | Option<**serde_json::Value**> | The object as Google holds it now. | [optional]
**object_locations** | **u32** | Branches Google kept on this member's object. | 
**sent_locations** | **u32** | Branches this member's card was sent, from our side. | 
**steps** | [**Vec<models::WalletStep>**](WalletStep.md) | Every request and Google's answer, in order. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


