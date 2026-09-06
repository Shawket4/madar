# ResultBlock

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**columns** | [**Vec<models::Column>**](Column.md) |  | 
**facet_by** | Option<**String**> |  | [optional]
**grain** | [**models::Grain**](Grain.md) |  | 
**period_from** | Option<**String**> |  | [optional]
**period_to** | Option<**String**> |  | [optional]
**preset_id** | Option<**String**> |  | [optional]
**row_count** | **u32** |  | 
**rows** | **Vec<std::collections::HashMap<String, serde_json::Value>>** |  | 
**scope** | [**models::ScopeInfo**](ScopeInfo.md) | Which branches this block covers. | 
**spec** | [**models::QuerySpec**](QuerySpec.md) | The exact query that produced this. Sending it back is what makes \"pin this answer to my dashboard\" a single client-side action: the spec is already a valid widget definition. | 
**title** | Option<**String**> | Set when the data came from a curated metric. | [optional]
**truncated** | **bool** |  | 
**viz** | [**models::Viz**](Viz.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


