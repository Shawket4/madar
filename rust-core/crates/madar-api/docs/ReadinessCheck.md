# ReadinessCheck

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**count** | **i64** | How many things the check counted: problems when it names them, else the things found (branches, sellable items, people). | 
**key** | **String** | Stable key the dashboards switch on, never localized: `branch`, `menu`, `payment`, `sign_in`, `tablet`, `items_no_category`, `items_zero_price`, `required_group_empty`, `menu_lint`, `recipes`, `ingredient_costs`, `team`, `receipt`. | 
**level** | [**models::CheckLevel**](CheckLevel.md) |  | 
**more** | **i64** | Problems past the first 20. | 
**ok** | **bool** |  | 
**problems** | [**Vec<models::ReadinessProblem>**](ReadinessProblem.md) | Up to 20 named problems. | 
**total** | Option<**i64**> | What `count` is out of, when that reads better as a share (recipes: of active items). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


