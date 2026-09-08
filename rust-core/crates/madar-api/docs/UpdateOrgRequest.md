# UpdateOrgRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**currency_code** | Option<**String**> |  | [optional]
**custom_branding** | Option<**bool**> | May this organisation wear its own mark and colours on the customer's card and signup page? A paid tier, and this endpoint is already super-admin only — which is the whole reason it lives here rather than with the other branding controls an org manager can reach. | [optional]
**is_active** | Option<**bool**> |  | [optional]
**logo_url** | Option<**String**> | `null` clears the logo; absent leaves it unchanged. To set a new logo, use `PUT /orgs/{id}/logo` (multipart) instead — JSON updates only accept the clear-to-null case here. | [optional]
**name** | Option<**String**> |  | [optional]
**receipt_footer** | Option<**String**> |  | [optional]
**slug** | Option<**String**> |  | [optional]
**tax_rate** | Option<**f64**> |  | [optional]
**timezone** | Option<**String**> | IANA timezone name (e.g. `Africa/Cairo`). Validated against the PostgreSQL timezone database. Branches inherit this when their own timezone is unset. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


