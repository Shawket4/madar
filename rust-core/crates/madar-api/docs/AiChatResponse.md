# AiChatResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**chart** | [**models::ChartHint**](ChartHint.md) | Suggested visualization for the result. | 
**columns** | [**Vec<models::Column>**](Column.md) | Column metadata for rendering the table/chart. | 
**facet_by** | Option<**String**> | When set, the client renders one section (chart + table) per distinct value of this column key — e.g. one table per branch (\"faceting\"). | [optional]
**provider** | **String** | Which model answered (e.g. \"gemini-2.5-flash\"). | 
**report_id** | **String** | The report the assistant chose. | 
**row_count** | **u32** |  | 
**rows** | **Vec<std::collections::HashMap<String, serde_json::Value>>** | Result rows, each an object keyed by column key. | 
**scope** | [**models::ScopeInfo**](ScopeInfo.md) | Which branches this answer covers. | 
**summary** | Option<**String**> | Optional one-sentence summary (only when `include_summary` was set and the model produced one), in the requested locale. | [optional]
**title** | **String** |  | 
**truncated** | **bool** | True when the result was capped. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


