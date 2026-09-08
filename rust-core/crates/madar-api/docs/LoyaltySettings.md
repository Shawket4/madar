# LoyaltySettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | `null` = the org-wide default. A branch id = that branch's override. | [optional]
**default_reward_cost** | **i32** | The cost offered by default when an admin adds a reward, in whatever this scope collects. Each reward may override it, so one catalogue holds \"espresso, 5 visits\" beside \"cake, 10 visits\". Also the pass's fallback target when no rewards have been curated yet. | 
**earn_include_tax** | **bool** | Add tax to the basis. Tips never earn and have no toggle. | 
**earn_on_discounted** | **bool** | Earn on what was actually paid rather than the pre-discount subtotal. | 
**earn_piastres_per_point** | **i32** | One point per this many piastres. 1000 = a point per 10 EGP. The dashboard shows and accepts EGP; the wire is always piastres. | 
**enabled** | **bool** | The program switch for this scope. | 
**mode** | **String** | What this scope collects: `\"points\"` (from money spent) or `\"visits\"` (one stamp per sale). One or the other — never both. | 
**org_id** | **uuid::Uuid** |  | 
**program_name** | **String** |  | 
**program_name_ar** | Option<**String**> |  | [optional]
**require_otp** | **bool** | Verify the signup phone by WhatsApp code, like bookings and ordering. | 
**reward_any_item** | Option<**bool**> | Any menu item may be taken as a reward, at `default_reward_cost`.  Off by default. A curated catalogue is the safer shape — it offers an espresso for five stamps without also offering the steak — and this is for the shops whose programme genuinely is \"collect five, get anything\", which a catalogue can only express by listing the entire menu and keeping that list in step with it forever.  The two are alternatives, not layers: with this on, the catalogue's per-item prices no longer apply, because an item's cost can no longer depend on which item it is.  Defaulted on the way in, because this type is the REQUEST body as well as the response: every till and dashboard already in the field sends a settings object without this key, and rejecting those would switch the programme off for everyone who had not updated yet. | [optional]
**terms** | Option<**String**> |  | [optional]
**terms_ar** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


