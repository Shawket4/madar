# \LoyaltyPublicApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**loyalty_apple_pass**](LoyaltyPublicApi.md#loyalty_apple_pass) | **GET** /public/loyalty/pass/{token}/apple.pkpass | Download the signed `.pkpass`.
[**loyalty_card**](LoyaltyPublicApi.md#loyalty_card) | **GET** /public/loyalty/card/{token} | A rewards card: the member's balance, progress to the next reward, rewards and wallet links.
[**loyalty_card_orders**](LoyaltyPublicApi.md#loyalty_card_orders) | **GET** /public/loyalty/card/{token}/orders | The member's own purchase history.
[**loyalty_card_qr**](LoyaltyPublicApi.md#loyalty_card_qr) | **GET** /public/loyalty/card/{token}/qr.png | The member's QR as a PNG.
[**loyalty_join**](LoyaltyPublicApi.md#loyalty_join) | **POST** /public/loyalty/join | Join a shop's rewards programme.
[**loyalty_join_info**](LoyaltyPublicApi.md#loyalty_join_info) | **GET** /public/loyalty/join-info | What a rewards programme's join page shows: its brand, rewards and what joining asks for.
[**public_loyalty_card_hero**](LoyaltyPublicApi.md#public_loyalty_card_hero) | **GET** /public/loyalty/brand/{org_id}/card/{revision}/{state} | The designed Google hero at one progress state (public: Google fetches it). No member data: the org, the revision and each track's progress, every number checked against the shop's tracks.
[**set_loyalty_card_preferences**](LoyaltyPublicApi.md#set_loyalty_card_preferences) | **POST** /public/loyalty/card/{token}/preferences | Save a card holder's choices: no marketing messages, and the language to write in.



## loyalty_apple_pass

> loyalty_apple_pass(token)
Download the signed `.pkpass`.

503s until Apple credentials are configured — see `wallet::apple::sign_manifest`. The button that leads here is only rendered when `apple::is_configured()`, so a customer does not meet this by accident.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Member token | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## loyalty_card

> models::CardView loyalty_card(token)
A rewards card: the member's balance, progress to the next reward, rewards and wallet links.

The token is the one on the card's barcode.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Member token from the pass barcode | [required] |

### Return type

[**models::CardView**](CardView.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## loyalty_card_orders

> models::PastOrders loyalty_card_orders(token)
The member's own purchase history.

Authenticated by the token in the URL — the same one their pass carries and the till scans — because that is the only credential a loyalty member has. Which means anyone holding the link can read it, and that is worth stating rather than glossing: a forwarded card link forwards the history with it. The shop decides whether to run a programme on those terms, and the privacy policy says so plainly.  Voided orders are excluded. A sale that was reversed is not something the customer bought, and showing it invites a question the page cannot answer.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Member token from the pass barcode | [required] |

### Return type

[**models::PastOrders**](PastOrders.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## loyalty_card_qr

> loyalty_card_qr(token)
The member's QR as a PNG.

Rendered server-side with the same renderer the printed cards use, rather than shipping a QR library to the browser — and rendered from the token DIRECTLY, never through a Shlink short link: a short URL is a public redirect, and the member token is the one value here that has to stay between the customer and the till.  This is the fallback that makes the program usable before either wallet is configured — and the answer for a customer whose phone has no wallet app.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Member token | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## loyalty_join

> models::JoinResult loyalty_join(join_input)
Join a shop's rewards programme.

Where `require_otp` is on, send the `device_token` from `/public/otp/verify`; until the phone is proven the answer carries no card.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**join_input** | [**JoinInput**](JoinInput.md) |  | [required] |

### Return type

[**models::JoinResult**](JoinResult.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## loyalty_join_info

> models::JoinInfo loyalty_join_info(branch_id, org_id)
What a rewards programme's join page shows: its brand, rewards and what joining asks for.

Name the shop with `org_id`, or a branch with `branch_id` from its counter code.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | The counter QR of one branch. Its settings and its catalogue apply. |  |
**org_id** | Option<**uuid::Uuid**> | The organisation's own code, for a shop that wants ONE card to hand out — a poster, a receipt footer, a link in a bio. The programme's org-level settings apply, which is also what the wallet pass has always used. |  |

### Return type

[**models::JoinInfo**](JoinInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## public_loyalty_card_hero

> public_loyalty_card_hero(org_id, revision, state)
The designed Google hero at one progress state (public: Google fetches it). No member data: the org, the revision and each track's progress, every number checked against the shop's tracks.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**revision** | **i32** |  | [required] |
**state** | **String** | e.g. `3-0-en.png` | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: image/png

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_loyalty_card_preferences

> set_loyalty_card_preferences(token, card_preferences)
Save a card holder's choices: no marketing messages, and the language to write in.

The card's own token is the key. Answers 204.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Member token from the pass barcode | [required] |
**card_preferences** | [**CardPreferences**](CardPreferences.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

