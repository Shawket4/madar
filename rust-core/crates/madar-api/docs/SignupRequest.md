# SignupRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**attribution** | Option<[**models::SignupAttribution**](SignupAttribution.md)> | The campaign tags the signup page was opened with, if any. Stored with the org for analysis only; a missing or odd value never refuses a signup. | [optional]
**code** | Option<**String**> |  | [optional]
**email** | **String** |  | 
**owner_name** | **String** |  | 
**password** | **String** | At least 8 characters. | 
**phone** | Option<**String**> | Deprecated, for the dashboard build before the verify step: the phone and code checked here instead of by `/public/signup/verify`. | [optional]
**shop_name** | **String** | The shop's name. It names the organization and its first branch. | 
**signup_token** | Option<**String**> | The token `POST /public/signup/verify` answered with: the proof that the owner holds the phone. The phone is the one it was issued for. | [optional]
**template** | **String** | `cafe` | `restaurant`: the role template the roles start from. | 
**terms_version** | **String** | The version of the terms the owner accepted (stored with the org). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


