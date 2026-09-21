# OrderNowContext

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**first_name** | **String** | First word of the name on file. | 
**full** | Option<[**models::OrderNowFull**](OrderNowFull.md)> |  | [optional]
**last_branch_name** | Option<**String**> | NAME only on the masked path; the full context carries the id. | [optional]
**logo_url** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**org_name** | **String** |  | 
**phone_hint** | **String** | `•••• 4567`. | 
**verify_required** | **bool** | True → this is the masked context; verify the phone (`/public/otp/request|verify`) and ask again with the device token. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


