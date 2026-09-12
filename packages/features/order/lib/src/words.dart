// The words the Sell / Floor / Bill screens say, resolved through the core.
//
// Every string still goes through `bridge.tr` first — that is the mechanism,
// and it is where the words belong. The table below exists because the
// vocabulary the redesign introduced ("Charge", "Seat", "Parked", "Bills")
// is not in `rust-core/crates/madar-core/src/i18n.rs` yet and this package
// cannot edit that crate. `tr` answers a missing key with the key itself, so
// this notices that and supplies the same English and Arabic the core will
// carry once the keys land; at that point every entry here is dead weight and
// the file can go.
import 'package:rust_bridge/rust_bridge.dart';

/// `bridge.tr(key)`, falling back to the local table for a key the core does
/// not have yet.
String orderWord(MadarBridge bridge, String key) {
  final fromCore = bridge.tr(key: key);
  if (fromCore != key) return fromCore;
  final table = bridge.isRtl() ? _ar : _en;
  return table[key] ?? fromCore;
}

const Map<String, String> _en = {
  // Sell
  'sell.takeaway': 'Takeaway',
  'sell.parked': 'Parked',
  'sell.park': 'Park',
  'sell.parked_empty': 'Nothing parked',
  'sell.this_round': 'This round',
  'sell.on_the_bill': 'On the bill',
  'sell.round_total': 'Round',
  'sell.bill_so_far': 'Bill so far (before tax)',
  'sell.charge': 'Charge',
  'sell.fire': 'Fire',
  'sell.table_required': 'Seat a table first',
  'sell.guest_name': 'Guest name',
  'sell.round_n': 'Round',
  // Floor
  'floor.title': 'Floor',
  'floor.seat': 'Seat',
  'floor.party_size': 'Party size',
  'floor.take_order': 'Take an order',
  'floor.unseat': 'Unseat (party left)',
  'floor.cleared': 'Cleared',
  'floor.seat_booking_here': 'Seat a booking here',
  'floor.walk_in_here': 'Walk-in here',
  'floor.no_bill_yet': 'No bill yet',
  // Bill
  'bill.title': 'Bill',
  'bill.void_bill': 'Void bill',
  'bill.gone': 'This bill was closed on another till',
  'bill.ready': 'Ready',
  'bill.queued': 'Queued',
  'bill.voided': 'Voided',
  // Bills (waiter tab)
  'bills.title': 'Bills',
  'bills.mine': 'Mine',
  'bills.others': 'Others',
  'bills.new_bill': 'New bill',
};

const Map<String, String> _ar = {
  // Sell
  'sell.takeaway': 'تيك أواي',
  'sell.parked': 'مركونة',
  'sell.park': 'اركن الطلب',
  'sell.parked_empty': 'لا طلبات مركونة',
  'sell.this_round': 'هذه الجولة',
  'sell.on_the_bill': 'على الفاتورة',
  'sell.round_total': 'الجولة',
  'sell.bill_so_far': 'الفاتورة حتى الآن (قبل الضريبة)',
  'sell.charge': 'تحصيل',
  'sell.fire': 'أرسل',
  'sell.table_required': 'أجلس على طاولة أولًا',
  'sell.guest_name': 'اسم الضيف',
  'sell.round_n': 'جولة',
  // Floor
  'floor.title': 'الصالة',
  'floor.seat': 'إجلاس',
  'floor.party_size': 'عدد الأفراد',
  'floor.take_order': 'خذ الطلب',
  'floor.unseat': 'إلغاء الإجلاس (غادروا)',
  'floor.cleared': 'تم التنظيف',
  'floor.seat_booking_here': 'أجلس حجزًا هنا',
  'floor.walk_in_here': 'زبون عابر هنا',
  'floor.no_bill_yet': 'لا فاتورة بعد',
  // Bill
  'bill.title': 'الفاتورة',
  'bill.void_bill': 'إلغاء الفاتورة',
  'bill.gone': 'أُغلقت هذه الفاتورة على جهاز آخر',
  'bill.ready': 'جاهز',
  'bill.queued': 'في الانتظار',
  'bill.voided': 'ملغى',
  // Bills (waiter tab)
  'bills.title': 'الفواتير',
  'bills.mine': 'فواتيري',
  'bills.others': 'الآخرون',
  'bills.new_bill': 'فاتورة جديدة',
};
