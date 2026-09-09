# LoyaltySettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**balance_cap** | Option<**i32**> | The ceiling, when `balance_cap_enabled`. `None` = derive it.  A `None` here is NOT \"no cap\" — that is what the switch is for. It means the most expensive reward on offer at this scope, read from the catalogue at award time. Once a customer can claim anything in the programme, collecting more buys them nothing and leaves the shop carrying a liability it never chose; and because it is derived, adding a dearer reward raises the ceiling without anyone retyping it.  Earning at the cap is DROPPED, not refused: the sale is not the customer's doing and must not fail because their card is full. | [optional]
**balance_cap_enabled** | Option<**bool**> | Whether a ceiling applies to what a member may hold at all.  Separate from the figure below, because \"no number\" has to be able to mean something. Off, a card collects without end. | [optional]
**birthday_enabled** | Option<**bool**> | Ask for a birthday at signup, and greet them on the day.  Off means the form does not ASK — not that it asks and ignores. A date of birth is the most sensitive thing this feature collects, and a shop that does not run birthday rewards has no business holding one. | [optional]
**birthday_message** | Option<**String**> | Overrides the built-in greeting. `{name}` is substituted; nothing else is. | [optional]
**birthday_message_ar** | Option<**String**> |  | [optional]
**birthday_reward_amount** | Option<**i32**> | Points or stamps given on the day. `None` is a greeting and nothing else, which is deliberately the default: plenty of shops want to say happy birthday without giving away a drink. | [optional]
**branch_id** | Option<**uuid::Uuid**> | `null` = the org-wide default. A branch id = that branch's override. | [optional]
**default_reward_cost** | **i32** | The cost offered by default when an admin adds a reward, in whatever this scope collects. Each reward may override it, so one catalogue holds \"espresso, 5 visits\" beside \"cake, 10 visits\". Also the pass's fallback target when no rewards have been curated yet. | 
**earn_include_tax** | **bool** | Add tax to the basis. Tips never earn and have no toggle. | 
**earn_on_discounted** | **bool** | Earn on what was actually paid rather than the pre-discount subtotal. | 
**earn_piastres_per_point** | **i32** | One point per this many piastres. 1000 = a point per 10 EGP. The dashboard shows and accepts EGP; the wire is always piastres. | 
**effective_balance_cap** | Option<**i32**> | The ceiling actually in force, once derived. **Read-only.**  `balance_cap` is what the shop TYPED, which is usually nothing; this is what that resolves to against the current catalogue. The dashboard shows it so \"leave it empty\" is a visible number rather than a promise, and so the figure on screen is the one the award path will use rather than the dashboard's own guess at it.  `null` when no ceiling applies. | [optional]
**enabled** | **bool** | The program switch for this scope. | 
**geofenced_branches** | Option<**i64**> | How many active branches have coordinates set. **Read-only.**  The one thing that decides whether a saved card can notify a customer when they are at the shop. Both wallets geofence from the branch coordinates on the pass, so a programme whose branches have none gets no location prompt on the phone and no nearby notification — and nothing anywhere said so, which reads as the wallet being broken rather than as a field nobody filled in.  Read-only in effect: this type doubles as the PUT body, and the write path binds its columns explicitly, so a value sent here is parsed and then ignored. It is a fact about `branches`, answered on this page because this is where someone wonders why the card is silent. | [optional]
**max_rewards_per_order** | Option<**i32**> | How many rewards one order may claim. `None` = unlimited.  `Some(1)` is the setting most shops mean when they ask for this: a member with thirty stamps and a five-stamp reward can otherwise take six free items in one visit, which is the same giveaway the shop believed it was spreading over six. | [optional]
**mode** | **String** | What this scope collects: `\"points\"` (from money spent) or `\"visits\"` (one stamp per sale). One or the other — never both. | 
**org_id** | **uuid::Uuid** |  | 
**program_name** | **String** |  | 
**program_name_ar** | Option<**String**> |  | [optional]
**require_otp** | **bool** | Verify the signup phone by WhatsApp code, like bookings and ordering. | 
**reward_any_item** | Option<**bool**> | Any menu item may be taken as a reward, at `default_reward_cost`.  Off by default. A curated catalogue is the safer shape — it offers an espresso for five stamps without also offering the steak — and this is for the shops whose programme genuinely is \"collect five, get anything\", which a catalogue can only express by listing the entire menu and keeping that list in step with it forever.  The two are alternatives, not layers: with this on, the catalogue's per-item prices no longer apply, because an item's cost can no longer depend on which item it is.  Defaulted on the way in, because this type is the REQUEST body as well as the response: every till and dashboard already in the field sends a settings object without this key, and rejecting those would switch the programme off for everyone who had not updated yet. | [optional]
**terms** | Option<**String**> |  | [optional]
**terms_ar** | Option<**String**> |  | [optional]
**winback_enabled** | Option<**bool**> | Nudge a member who has not been in for a while. Off by default, like everything here that speaks to a customer unprompted.  The timing is not a per-shop setting: how long \"a while\" is, whether it repeats, and how stale is too stale are one operational judgement across the estate, and they live in the environment (`LOYALTY_WINBACK_*`) rather than in a form where a shop could set it to a day and burn its own list down. | [optional]
**winback_message** | Option<**String**> | ONE override, in whichever language the shop writes it, replacing the built-in English and Arabic both. `{name}` is substituted; nothing else.  Unset is the better default: the built-ins are written in each language rather than translated into one, so a customer reads a sentence that was composed for them. | [optional]
**winback_reward_amount** | Option<**i32**> | Points or stamps to arrive with the nudge. `None` is words only. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


