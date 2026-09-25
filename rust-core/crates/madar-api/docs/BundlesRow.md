# BundlesRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cost** | **i64** |  | 
**cost_missing** | **bool** | True when any line's cost was unknown (`cost` then counts the known part). | 
**id** | **uuid::Uuid** | The combo's menu item id, or the deal rule's id. | 
**kind** | **String** | `combo` | `deal`. | 
**list_value** | **i64** | The same lines at their normal prices. | 
**margin** | Option<**String**> | `(revenue − cost) / revenue` as a fraction string; `null` when revenue is 0. | [optional]
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**orders** | **i64** |  | 
**revenue** | **i64** | A combo: Σ its parts' line_total + their add-ons. A deal: Σ the consumed lines' line_total (after the deal). | 
**saving** | **i64** | `list_value − revenue`. | 
**sold** | **i64** | Combo units (Σ header quantity, refunds netted) or deal applications (Σ times). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


