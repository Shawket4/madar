# CardPreferences

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**locale** | Option<**String**> | The language they are reading this page in.  Sent by the page itself rather than chosen in a form. We stored whatever their phone said at signup, and a phone that has since changed language is a customer still being written to in the wrong one. Opening their own card is the moment we can tell. | [optional]
**marketing_opt_out** | Option<**bool**> | Stop sending marketing. Covers the birthday greeting as well as the win-back: someone asking us to stop is asking the SHOP to stop, not to be excluded from one campaign. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


