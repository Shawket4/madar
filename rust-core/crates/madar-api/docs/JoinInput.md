# JoinInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**device_token** | Option<**String**> | Device-trust token from `/public/otp/verify`. Required only when the branch's `require_otp` is on. | [optional]
**locale** | Option<**String**> | 'en' or 'ar' — the language the pass is written in. | [optional]
**name** | **String** |  | 
**phone** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


