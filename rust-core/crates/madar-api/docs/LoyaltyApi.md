# \LoyaltyApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**delete_loyalty_settings**](LoyaltyApi.md#delete_loyalty_settings) | **DELETE** /loyalty/settings | 
[**get_loyalty_member**](LoyaltyApi.md#get_loyalty_member) | **GET** /loyalty/members/{id} | 
[**get_loyalty_reward_items**](LoyaltyApi.md#get_loyalty_reward_items) | **GET** /loyalty/reward-items | 
[**get_loyalty_settings**](LoyaltyApi.md#get_loyalty_settings) | **GET** /loyalty/settings | 
[**get_loyalty_wallet_status**](LoyaltyApi.md#get_loyalty_wallet_status) | **GET** /loyalty/wallet-status | Why there is no \"Add to Wallet\" button.
[**list_loyalty_members**](LoyaltyApi.md#list_loyalty_members) | **GET** /loyalty/members | 
[**loyalty_adjust**](LoyaltyApi.md#loyalty_adjust) | **POST** /loyalty/adjust | 
[**loyalty_award**](LoyaltyApi.md#loyalty_award) | **POST** /loyalty/award | The live route. Tellers press the button; the permission is the same `update` the redeem action needs.
[**loyalty_lookup**](LoyaltyApi.md#loyalty_lookup) | **POST** /loyalty/lookup | Identify the member in front of the till.
[**preview_loyalty_birthday_message**](LoyaltyApi.md#preview_loyalty_birthday_message) | **POST** /loyalty/birthday-preview | Render the greeting for settings that have NOT been saved yet.
[**put_loyalty_reward_items**](LoyaltyApi.md#put_loyalty_reward_items) | **PUT** /loyalty/reward-items | 
[**put_loyalty_settings**](LoyaltyApi.md#put_loyalty_settings) | **PUT** /loyalty/settings | 



## delete_loyalty_settings

> delete_loyalty_settings(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Omit for the org-wide default; supply a branch for its override. |  |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_loyalty_member

> models::MemberDetail get_loyalty_member(id, branch_id, q, limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Member ID | [required] |
**branch_id** | Option<**uuid::Uuid**> | Scopes the thresholds shown. Omit to use the org default. |  |
**q** | Option<**String**> | Name or phone fragment. |  |
**limit** | Option<**i64**> |  |  |
**offset** | Option<**i64**> |  |  |

### Return type

[**models::MemberDetail**](MemberDetail.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_loyalty_reward_items

> models::RewardCatalogue get_loyalty_reward_items(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Omit for the org-wide default; supply a branch for its override. |  |

### Return type

[**models::RewardCatalogue**](RewardCatalogue.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_loyalty_settings

> models::LoyaltySettings get_loyalty_settings(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Omit for the org-wide default; supply a branch for its override. |  |

### Return type

[**models::LoyaltySettings**](LoyaltySettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_loyalty_wallet_status

> models::WalletStatus get_loyalty_wallet_status(branch_id)
Why there is no \"Add to Wallet\" button.

Every failure in this feature has looked the same from the outside — a missing button, or a save that says \"something went wrong\" — while the cause was a variable nobody set, a key file the code never read, a service account Google had not been told about, or a link over a size limit. None of those reach a customer's screen, and only some reach a log.  This asks, on demand, and reports what it finds. It makes live calls to Google, so it is deliberately not part of any page load.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Omit for the org-wide default; supply a branch for its override. |  |

### Return type

[**models::WalletStatus**](WalletStatus.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_loyalty_members

> models::MembersPage list_loyalty_members(branch_id, q, limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Scopes the thresholds shown. Omit to use the org default. |  |
**q** | Option<**String**> | Name or phone fragment. |  |
**limit** | Option<**i64**> |  |  |
**offset** | Option<**i64**> |  |  |

### Return type

[**models::MembersPage**](MembersPage.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## loyalty_adjust

> models::MemberView loyalty_adjust(adjust_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**adjust_request** | [**AdjustRequest**](AdjustRequest.md) |  | [required] |

### Return type

[**models::MemberView**](MemberView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## loyalty_award

> models::AwardResult loyalty_award(award_request)
The live route. Tellers press the button; the permission is the same `update` the redeem action needs.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**award_request** | [**AwardRequest**](AwardRequest.md) |  | [required] |

### Return type

[**models::AwardResult**](AwardResult.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## loyalty_lookup

> models::ScanResult loyalty_lookup(lookup_request)
Identify the member in front of the till.

A POST rather than a GET because the member token is a bearer-ish secret: in a query string it would land in access logs, browser history and any proxy in between.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**lookup_request** | [**LookupRequest**](LookupRequest.md) |  | [required] |

### Return type

[**models::ScanResult**](ScanResult.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## preview_loyalty_birthday_message

> models::BirthdayPreview preview_loyalty_birthday_message(loyalty_settings)
Render the greeting for settings that have NOT been saved yet.

Rendered by the server, from the same `message_for` the sweep uses, because a preview reimplemented in the dashboard is a preview that drifts — and the thing it would drift from is a message sent once a year to a customer, where nobody would ever catch it.  Takes the settings being edited rather than reading the stored ones: the point is to see what you are about to save.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**loyalty_settings** | [**LoyaltySettings**](LoyaltySettings.md) |  | [required] |

### Return type

[**models::BirthdayPreview**](BirthdayPreview.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_loyalty_reward_items

> models::RewardCatalogue put_loyalty_reward_items(put_reward_items)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**put_reward_items** | [**PutRewardItems**](PutRewardItems.md) |  | [required] |

### Return type

[**models::RewardCatalogue**](RewardCatalogue.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_loyalty_settings

> models::LoyaltySettings put_loyalty_settings(loyalty_settings)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**loyalty_settings** | [**LoyaltySettings**](LoyaltySettings.md) |  | [required] |

### Return type

[**models::LoyaltySettings**](LoyaltySettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

