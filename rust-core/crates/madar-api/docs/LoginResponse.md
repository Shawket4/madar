# LoginResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**currency_code** | **String** |  | 
**tax_rate** | **f64** | Org tax rate as a decimal (e.g. 0.14 = 14% VAT); 0.0 when no org. Mirrors /auth/me so the POS has it immediately after login. | 
**token** | **String** | JWT to send as `Authorization: Bearer <token>` on subsequent requests. | 
**user** | [**models::UserPublic**](UserPublic.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


