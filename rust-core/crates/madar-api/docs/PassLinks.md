# PassLinks

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**any** | **bool** | False when neither wallet is configured — the site shows the member's QR on the page instead of dead buttons. | 
**apple_url** | Option<**String**> | Downloads the signed `.pkpass`. Site-relative, because the signup page is served from the same origin as the API — so a pass needs a CERTIFICATE, not a configured base URL. | [optional]
**google_url** | Option<**String**> | `https://pay.google.com/gp/v/save/<jwt>`. | [optional]
**nearby** | **bool** | This pass carries at least one branch location, so the phone CAN surface it near a shop — if the customer has let their wallet app do that.  The permission belongs to the wallet app and no web page can grant it, so the card page can only explain where it lives. Explaining it to someone whose shop has no coordinates on any branch would be worse than saying nothing: the steps would work and the card still would not appear. Hence a flag rather than an assumption. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


