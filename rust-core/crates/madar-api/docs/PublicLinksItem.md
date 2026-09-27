# PublicLinksItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_names** | **Vec<String>** | Order / book: the branches where it is on. | 
**channels** | **Vec<String>** | Order: the channels on anywhere — `pickup`, `delivery`, `in_mall`, `umbrella`. | 
**href** | **String** | Absolute. For a module: the shop's own host when it has one, else the generic host. For a custom link: the shop's URL. | 
**kind** | [**models::LinksItemKind**](LinksItemKind.md) |  | 
**path** | Option<**String**> | Modules only: the same place as a path on the shop's own host, for a page being read ON that host. | [optional]
**title_ar** | Option<**String**> |  | [optional]
**title_en** | Option<**String**> | Custom links only (a module's title is the page's own words). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


