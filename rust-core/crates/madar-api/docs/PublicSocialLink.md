# PublicSocialLink

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**key** | **String** | One of `orgs::social::PLATFORMS` — what the page picks its glyph by. | 
**label** | **String** | What a human calls it. The page falls back to this where it has no glyph for `key`, so a platform added on the server still renders. | 
**url** | **String** | `https://…` and nothing else — checked on write and again on read, see `orgs::social::links_of`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


