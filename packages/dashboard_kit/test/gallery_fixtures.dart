// Fixture copy and data for the kit's gallery — the fictional "Sabah Coffee"
// group in Cairo. Test-only words; the app's come through the i18n.

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';

class L {
  const L(this.lang);
  final String lang;
  bool get ar => lang == 'ar';
  String s(String en, String arabic) => ar ? arabic : en;

  String get orders => s('Orders', 'الطلبات');
  String get ordersSub => s(
    'Every sale across your branches, newest first.',
    'كل المبيعات في فروعك، الأحدث أولًا.',
  );
  String get add => s('New order', 'طلب جديد');
  String get all => s('All', 'الكل');
  String get today => s('Today', 'اليوم');
  String get week => s('This week', 'هذا الأسبوع');
  String get history => s('History', 'السجل');
  String get searchOrders =>
      s('Search by order number or customer', 'ابحث برقم الطلب أو العميل');
  String get status => s('Status', 'الحالة');
  String get allStatuses => s('All statuses', 'كل الحالات');
  String get branch => s('Branch', 'الفرع');
  String get allBranches => s('All branches', 'كل الفروع');
  String get flagged => s('Flagged only', 'المُعلّمة فقط');
  String get sales => s('Net sales', 'صافي المبيعات');
  String get ordersCount => s('Orders', 'الطلبات');
  String get avgTicket => s('Average ticket', 'متوسط الفاتورة');
  String get voids => s('Voids', 'الإلغاءات');
  String get vsLast => s('vs last week', 'مقارنةً بالأسبوع الماضي');
  String get approve => s('Approve', 'موافقة');
  String get ref => s('Order', 'الطلب');
  String get time => s('Time', 'الوقت');
  String get customer => s('Customer', 'العميل');
  String get channel => s('Channel', 'القناة');
  String get total => s('Total', 'الإجمالي');
  String get paid => s('Paid', 'مدفوع');
  String get open => s('Open', 'مفتوح');
  String get voided => s('Voided', 'ملغي');
  String get refunded => s('Refunded', 'مسترد');
  String get pending => s('Pending', 'قيد الانتظار');
  String get dineIn => s('Dine-in', 'في المطعم');
  String get takeaway => s('Takeaway', 'تيك أواي');
  String get delivery => s('Delivery', 'توصيل');
  String get talabat => s('Talabat', 'طلبات');
  String get noOrders => s(
    'Orders will show here as soon as a till rings one up.',
    'ستظهر الطلبات هنا فور تسجيل أول طلب على الخزينة.',
  );
  String get noOrdersTitle =>
      s('No orders in this period', 'لا توجد طلبات في هذه الفترة');
  String get network => s(
    'The server did not answer. Check the connection and try again.',
    'لم يستجب الخادم. تحقق من الاتصال وحاول مجددًا.',
  );
  String get void_ => s('Void', 'إلغاء الطلب');
  String get print => s('Print', 'طباعة');
  String get name => s('Name', 'الاسم');
  String get nameHint =>
      s('As it appears on the menu.', 'كما يظهر في القائمة.');
  String get notes => s('Notes', 'ملاحظات');
  String get price => s('Price', 'السعر');
  String get discount => s('Discount', 'الخصم');
  String get quantity => s('Par level', 'الحد الأدنى للمخزون');
  String get category => s('Category', 'الفئة');
  String get hot => s('Hot drinks', 'مشروبات ساخنة');
  String get cold => s('Cold drinks', 'مشروبات باردة');
  String get bakery => s('Bakery', 'مخبوزات');
  String get tags => s('Stations', 'المحطات');
  String get bar => s('Bar', 'البار');
  String get kitchen => s('Kitchen', 'المطبخ');
  String get pastry => s('Pastry', 'الحلويات');
  String get active => s('Active', 'نشط');
  String get activeHint => s(
    'Inactive items stay off every till.',
    'العناصر غير النشطة لا تظهر على أي خزينة.',
  );
  String get taxable =>
      s('Charge VAT on this item', 'احتساب ضريبة القيمة المضافة على هذا الصنف');
  String get size => s('Default size', 'الحجم الافتراضي');
  String get small => s('Small', 'صغير');
  String get medium => s('Medium', 'وسط');
  String get large => s('Large', 'كبير');
  String get view => s('View', 'العرض');
  String get daily => s('Daily', 'يومي');
  String get weekly => s('Weekly', 'أسبوعي');
  String get monthly => s('Monthly', 'شهري');
  String get startDate => s('Starts on', 'يبدأ في');
  String get opensAt => s('Opens at', 'يفتح في');
  String get tz => s('Timezone', 'المنطقة الزمنية');
  String get itemName => s('Item name', 'اسم الصنف');
  String get brandColor => s('Accent colour', 'لون العلامة');
  String get photo => s('Photo', 'الصورة');
  String get photoHint => s(
    'PNG, JPEG or WebP, up to 5 MB.',
    'PNG أو JPEG أو WebP، حتى 5 ميجابايت.',
  );
  String get required => s('Give the item a name.', 'أدخل اسمًا للصنف.');
  String get period => s('Pay period', 'فترة الرواتب');
  String get editItem => s('Edit Flat White', 'تعديل فلات وايت');
  String get editItemSub => s(
    'Changes reach every till on its next sync.',
    'تصل التغييرات إلى كل خزينة عند المزامنة التالية.',
  );
  String get deleteBranch =>
      s('Delete the Zamalek branch?', 'حذف فرع الزمالك؟');
  String get deleteBranchSub => s(
    'Its 3 tills stop syncing. This can\'t be undone.',
    'ستتوقف خزائنه الثلاث عن المزامنة. لا يمكن التراجع عن ذلك.',
  );
  String get orderTitle => s('Order #1042', 'الطلب رقم 1042');
  String get orderSub =>
      s('Heliopolis · Till 2 · Sara', 'مصر الجديدة · الخزينة 2 · سارة');
  String get saved => s('Changes saved', 'تم حفظ التغييرات');
  String get failed => s(
    'You do not have permission to void orders.',
    'ليست لديك صلاحية إلغاء الطلبات.',
  );
  String get salesTrend => s('Sales by day', 'المبيعات حسب اليوم');
  String get salesTrendSub =>
      s('Net of refunds, last 14 days', 'بعد خصم المرتجعات، آخر 14 يومًا');
  String get byChannel => s('Orders by channel', 'الطلبات حسب القناة');
  String get byBranch => s('Sales by branch', 'المبيعات حسب الفرع');
  String get payMix => s('Payment mix', 'طرق الدفع');
  String get cash => s('Cash', 'نقدي');
  String get card => s('Card', 'بطاقة');
  String get wallet => s('Wallet', 'محفظة');
  String get thisWeek => s('This week', 'هذا الأسبوع');
  String get lastWeek => s('Last week', 'الأسبوع الماضي');
  String get settings => s('Settings', 'الإعدادات');
  String get brand => s('Brand', 'العلامة التجارية');
  String get payments => s('Payment methods', 'طرق الدفع');
  String get members => s('Team members', 'أعضاء الفريق');
  String get cashIn => s('Cash in · float', 'إيداع نقدي · رصيد افتتاحي');
  String get payout => s('Pay out · milk delivery', 'صرف · توريد الحليب');
  String get subtotal => s('Subtotal', 'المجموع الفرعي');
  String get vat => s('VAT 14%', 'ضريبة 14%');
  String get grand => s('Total', 'الإجمالي');
  String get stockLow => s('Low on oat milk', 'حليب الشوفان قارب على النفاد');
  String get section => s('Today\'s tills', 'خزائن اليوم');
  String get sectionSub =>
      s('Open and closed, across branches.', 'المفتوحة والمغلقة في كل الفروع.');
  String get progress => s('Shift target', 'هدف الوردية');
  String get menuItems => s('Menu items', 'أصناف القائمة');
  String get costLabel => s('Cost', 'التكلفة');
}

class Order {
  const Order(
    this.ref,
    this.time,
    this.customer,
    this.channel,
    this.total,
    this.status,
  );
  final String ref;
  final String time;
  final String customer;
  final int channel;
  final int total;
  final int status;
}

const orders = [
  Order('1042', '06:02 PM', 'Mona Adel', 0, 19000, 0),
  Order('1041', '05:48 PM', 'Karim Hassan', 1, 42850, 0),
  Order('1040', '05:30 PM', 'Youssef Nabil', 2, 123450, 1),
  Order('1039', '04:55 PM', 'Salma Fathy', 3, 5000, 2),
  Order('1038', '04:10 PM', 'Omar Samir', 0, 8600, 3),
  Order('1037', '03:41 PM', 'Laila Mostafa', 1, 31200, 0),
  Order('1036', '02:05 PM', 'Ahmed Tarek', 2, 256000, 4),
  Order('1035', '01:18 PM', 'Nour Ibrahim', 0, 14500, 0),
  Order('1034', '12:52 PM', 'Hana Ezzat', 1, 9900, 0),
  Order('1033', '12:07 PM', 'Mahmoud Reda', 0, 61000, 0),
  Order('1032', '11:40 AM', 'Dina Sherif', 3, 22300, 0),
  Order('1031', '11:02 AM', 'Tamer Wael', 0, 7500, 0),
];

const customersAr = [
  'منى عادل',
  'كريم حسن',
  'يوسف نبيل',
  'سلمى فتحي',
  'عمر سمير',
  'ليلى مصطفى',
  'أحمد طارق',
  'نور إبراهيم',
  'هنا عزت',
  'محمود رضا',
  'دينا شريف',
  'تامر وائل',
];

String customerOf(L l, Order o) =>
    l.ar ? customersAr[orders.indexOf(o)] : o.customer;

String channelOf(L l, int c) =>
    [l.dineIn, l.takeaway, l.delivery, l.talabat][c];

(String, DashTone) statusOf(L l, int s) => [
  (l.paid, DashTone.success),
  (l.open, DashTone.accent),
  (l.pending, DashTone.warning),
  (l.voided, DashTone.danger),
  (l.refunded, DashTone.info),
][s];

List<DashColumn<Order>> orderColumns(BuildContext context, L l) {
  final f = context.dashFormats;
  return [
    DashColumn(
      id: 'ref',
      label: l.ref,
      text: (o) => '#${o.ref}',
      numeric: true,
      align: DashAlign.start,
      width: 104,
      sortValue: (o) => o.ref,
      phone: DashPhoneRole.title,
    ),
    DashColumn(
      id: 'time',
      label: l.time,
      text: (o) => o.time,
      width: 120,
      numeric: true,
      align: DashAlign.start,
    ),
    DashColumn(
      id: 'customer',
      label: l.customer,
      text: (o) => customerOf(l, o),
      flex: 2,
      sortValue: (o) => customerOf(l, o),
    ),
    DashColumn(
      id: 'channel',
      label: l.channel,
      text: (o) => channelOf(l, o.channel),
    ),
    DashColumn(
      id: 'status',
      label: l.status,
      text: (o) => statusOf(l, o.status).$1,
      cell: (context, o) {
        final (label, tone) = statusOf(l, o.status);
        return DashStatusPill(label: label, tone: tone);
      },
      width: 136,
      hideable: true,
    ),
    DashColumn(
      id: 'total',
      label: l.total,
      text: (o) => f.money(o.total),
      numeric: true,
      width: 140,
      sortValue: (o) => o.total,
    ),
  ];
}

const salesByDay = <double>[
  1840000.0,
  2210000,
  1985000,
  2460000,
  2720000,
  3105000,
  2890000,
  2010000,
  2340000,
  2190000,
  2650000,
  2980000,
  3320000,
  3010000,
];
const salesLastWeek = <double>[
  1720000.0,
  1950000,
  2080000,
  2210000,
  2400000,
  2860000,
  2700000,
  1900000,
  2100000,
  2050000,
  2400000,
  2700000,
  3050000,
  2800000,
];
