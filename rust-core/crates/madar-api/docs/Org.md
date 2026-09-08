# Org

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**brand_accent** | Option<**String**> |  | [optional]
**brand_background** | Option<**String**> | The card palette derived from `logo_url` when it was uploaded (`orgs::branding`). Read-only over the API: there is nothing to set, and nothing a client may set — the point of deriving is that a shop cannot choose two colours nobody can read. | [optional]
**brand_foreground** | Option<**String**> |  | [optional]
**brand_logo_is_mark** | Option<**bool**> | True when the logo is a shape on transparency, so a card may repaint it for contrast (`branding::is_mark`). NULL until it has been looked at. | [optional]
**currency_code** | **String** |  | 
**custom_branding** | **bool** | The branding tier. Super admin only — see `UpdateOrgRequest`. | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**logo_url** | Option<**String**> |  | [optional]
**name** | **String** |  | 
**receipt_footer** | Option<**String**> |  | [optional]
**slug** | **String** |  | 
**tax_rate** | **f64** | Tax rate as a decimal (e.g. `0.14` for 14% VAT). Stored as `BigDecimal` internally; transmitted as a JSON number. | 
**timezone** | **String** | IANA timezone name. The org-level default that branches inherit when their own timezone is unset. Defaults to `Africa/Cairo`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


