# QuerySpec

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch** | Option<**String**> | Narrow to ONE branch by name. Fuzzy-matched *within* the caller's accessible branches, so it can only ever narrow, never widen. Dashboards use the request-level scope instead and leave this unset. | [optional]
**compare** | Option<[**models::Compare**](Compare.md)> | Period-over-period comparison. | [optional]
**dataset** | **String** | Dataset id — fixes the grain. See `GET /metrics/schema`. | 
**dimensions** | Option<**Vec<String>**> | GROUP BY axes, outermost first. Empty = a single total row. | [optional]
**filters** | Option<**std::collections::HashMap<String, String>**> | Filter id → chosen value. Each value selects a pre-written predicate. | [optional]
**having_min** | Option<**i64**> | Only keep groups whose sort measure reaches this value. | [optional]
**limit** | Option<**u32**> | Row cap, clamped to [`MAX_LIMIT`]. | [optional]
**measures** | Option<**Vec<String>**> | Aggregates to compute. Empty = the dataset's headline measures. | [optional]
**period** | Option<[**models::Period**](Period.md)> |  | [optional]
**sort** | Option<[**models::Sort**](Sort.md)> | Which measure orders the result, and in which direction. | [optional]
**transform** | Option<[**models::Transform**](Transform.md)> |  | [optional]
**viz** | Option<[**models::Viz**](Viz.md)> | Preferred visualization. Omitted or [`Viz::Auto`] lets the backend pick from the result shape. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


