# MenuEngineeringRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**category_name** | Option<**String**> |  | [optional]
**class** | **String** | star | workhorse | challenge | dog (Foodics names). | 
**cost_missing_lines** | **i64** | Lines in the window whose sale-time cost could not be resolved. Always reports snapshot data quality, regardless of `cost_basis` — under `current`, an included row can still carry snapshot gaps. | 
**item_name** | **String** |  | 
**item_profit** | **i64** | Average profit per unit, piastres (`(sales - cost) / qty`). | 
**menu_item_id** | **uuid::Uuid** |  | 
**popularity_category** | **String** | \"high\" | \"low\" — Kasavana-Smith 70% rule (0.70 / n). | 
**popularity_pct** | **f64** | Share of units among the rows in this report (cost-tracked only). | 
**profit_category** | **String** | \"high\" | \"low\" — vs weighted-average per-unit profit. | 
**quantity_sold** | **i64** | Units sold (standalone lines only — bundle lines are excluded so the per-unit economics stay clean; bundle performance has its own report). | 
**sales** | **i64** | Revenue from those lines, piastres. | 
**size_label** | **String** | `\"one_size\"` for items without sizes. | 
**total_cost** | **i64** | Recipe-scope COGS in piastres (additive addons excluded — they have their own revenue and their own report). Snapshot basis: `SUM(unit_cost × quantity)`; current basis: today's recipe rollup × quantity. Rows where this is unresolvable are excluded from the report, so it is always present. | 
**total_profit** | **i64** | `sales - total_cost`, piastres. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


