# GoogleObjectDump

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**error** | Option<**String**> | Why there is no object, in Google's words. | [optional]
**expected_locations** | **u32** | Branches this member's card should be pinned to, from our own side. | 
**object** | Option<**serde_json::Value**> | Google's object, untouched. `None` when the read itself failed. | [optional]
**stored_locations** | **u32** | Branches Google says are on it. A gap between the two is the answer. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


