/// What is left of the checkout feature's own kit: the payment-glyph and
/// brand-hex helpers. Its button, field, section label, amount field and
/// hairline are the design system's now — see `design_system/controls.dart`
/// for why six copies of each was not a neutral cost.
library;

/// Map a backend payment-icon token to a shared icon-catalog glyph —
/// mirrors the natives' payGlyph / the Swift PayChip.symbol() mapping.
String payGlyph(String icon) => switch (icon.toLowerCase()) {
  'money' || 'cash' || 'banknote' => 'banknote',
  'credit_card' ||
  'card' ||
  'creditcard' ||
  'visa' ||
  'mastercard' ||
  'debit' => 'creditcard',
  'wallet' || 'ewallet' || 'e_wallet' => 'wallet',
  'pie_chart' => 'chart.pie',
  'delivery' => 'bicycle',
  'qr_code' || 'qr' => 'qrcode',
  'bank' || 'transfer' || 'bank_transfer' => 'bank',
  'gift_card' => 'gift',
  'smartphone' || 'phone' || 'mobile' || 'vodafone' || 'instapay' => 'iphone',
  'receipt' => 'receipt',
  'store' => 'storefront',
  'star' => 'star',
  'link' => 'link',
  _ => 'banknote',
};
