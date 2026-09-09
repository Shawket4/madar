# PassLinks

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**any** | **bool** | False when neither wallet is configured — the site shows the member's QR on the page instead of dead buttons. | 
**apple_url** | Option<**String**> | Downloads the signed `.pkpass`. Site-relative, because the signup page is served from the same origin as the API — so a pass needs a CERTIFICATE, not a configured base URL. | [optional]
**google_url** | Option<**String**> | `https://pay.google.com/gp/v/save/<jwt>`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


