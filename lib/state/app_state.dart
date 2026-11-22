import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/roles.dart';
import '../core/l10n/app_strings.dart';
import '../core/utils/app_format.dart';
import '../core/utils/id_gen.dart';
import '../data/models/audit_entry.dart';
import '../data/models/customer.dart';
import '../data/models/medicine.dart';
import '../data/models/purchase_order.dart';
import '../data/models/reporting_models.dart';
import '../data/models/sale.dart';
import '../data/models/staff_user.dart';
import '../data/models/supplier.dart';
import '../data/seed/seed_data.dart';
import '../domain/inventory_rules.dart';
import '../domain/medicine_registration.dart';
import '../domain/permissions.dart';
import '../domain/reporting_rules.dart';

/// One entry of the screen stack (S.stack in the HTML). [name] is a key of the
/// SCREENS map: home, inventory, sales, medicine, register, chat, reports,
/// audit, finance, suppliers, stocktake, alternatives, credit, customer,
/// rxlog, orders, settings.
class NavEntry {
  const NavEntry(this.name, [this.params = const {}]);
  final String name;
  final Map<String, Object?> params;
}

enum LayoutStyle { classic, modern }

/// The single source of truth, equivalent of the `S` object in the HTML.
/// Screens read it with context.watch<AppState>() and change it through the
/// methods below. Replace the in-memory lists with a repository later
/// (see docs/PORTING_MAP.md, "Data layer").
class AppState extends ChangeNotifier {
  AppState() {
    meds = SeedData.medicines();
    sales = SeedData.sales(meds);
    customers = SeedData.customers();
    orders = SeedData.orders();
    rxRegister = SeedData.rxRegister();
    supplierInvoices = SeedData.supplierInvoices();
    missedSales = SeedData.missedSales();
    expenses = SeedData.expenses();
    audit = SeedData.audit(who);
    for (final s in SeedData.suppliers) {
      _suppliers[s.id] = s;
    }
  }

  // ---- session ------------------------------------------------------------
  bool signedIn = false;
  UserRole role = UserRole.owner;
  String userName = 'Selam';
  final List<StaffUser> staff = [];
  PharmacyProfile profile = PharmacyProfile();

  bool can(Perm p) => roleCan(role, p);
  bool get canEdit => roleCanEdit(role);
  String get who => '$userName (${role.label})';

  void signIn(StaffUser user) {
    userName = user.name;
    role = user.role;
    signedIn = true;
    stack
      ..clear()
      ..add(const NavEntry('home'));
    _touch();
  }

  void signOut() {
    signedIn = false;
    _touch();
  }

  // ---- appearance / language / connectivity -------------------------------
  AppLang lang = AppLang.en;
  ThemeMode themeMode = ThemeMode.light;
  LayoutStyle layout = LayoutStyle.classic;
  bool online = true;
  int pending = 0; // changes waiting to sync
  int alertDays = defaultAlertDays;
  final Map<String, int> categoryAlertDays = {};

  void setLang(AppLang l) {
    lang = l;
    AppStrings.lang = l;
    AppFormat.amharicLabels = l == AppLang.am;
    _touch();
  }

  void toggleLang() => setLang(lang == AppLang.en ? AppLang.am : AppLang.en);

  void setTheme(ThemeMode m) {
    themeMode = m;
    _touch();
  }

  void setEthiopianCalendar(bool on) {
    AppFormat.ethiopianCalendar = on;
    _touch();
  }

  void setLayout(LayoutStyle l) {
    layout = l;
    _touch();
  }

  void toggleOnline() {
    online = !online;
    if (online) pending = 0; // preview: pretend the queue synced
    _touch();
  }

  // ---- navigation (stack of screens) --------------------------------------
  final List<NavEntry> stack = [const NavEntry('home')];
  NavEntry get current => stack.last;
  String get tab => stack.first.name;

  void goTab(String name) {
    stack
      ..clear()
      ..add(NavEntry(name));
    _touch();
  }

  void go(String name, [Map<String, Object?> params = const {}]) {
    stack.add(NavEntry(name, params));
    _touch();
  }

  bool back() {
    if (stack.length > 1) {
      stack.removeLast();
      _touch();
      return true;
    }
    return false;
  }

  // ---- data ---------------------------------------------------------------
  late List<Medicine> meds;
  late List<SaleLine> sales;
  late List<Customer> customers;
  late List<PurchaseOrder> orders;
  late List<RxRegisterEntry> rxRegister;
  late List<SupplierInvoice> supplierInvoices;
  late List<MissedSale> missedSales;
  late List<ExpenseEntry> expenses;
  late List<AuditEntry> audit;
  final Map<String, Supplier> _suppliers = {};
  final Map<String, String> receiptNo = {}; // sale id -> RC-00001
  final Map<String, List<PaymentPart>> payments = {}; // sale id -> parts
  String lastSaleId = '';

  double taxRateInPrices = 0;
  MonthlyReportSettings monthlyReport = const MonthlyReportSettings();

  Map<String, Supplier> get suppliers => _suppliers;
  Supplier supplierOf(String id) =>
      _suppliers[id] ??
      const Supplier(id: '', name: '—', phone: '', termsDays: 0, leadDays: 0);
  Medicine? medById(String id) {
    for (final m in meds) {
      if (m.id == id) return m;
    }
    return null;
  }

  InventoryRules? _rules;
  InventoryRules get rules => _rules ??= InventoryRules(
        meds: meds,
        sales: sales,
        orders: orders,
        suppliers: _suppliers,
        alertDays: alertDays,
        categoryAlertDays: categoryAlertDays,
      );

  /// Call after every data change so derived values are recalculated.
  void _touch() {
    _rules = null;
    notifyListeners();
  }

  void refresh() => _touch();

  /// log() in the HTML: append an audit entry (newest first).
  void log(String type, String action,
      [String detail = '',
      double? amount,
      String ref = '',
      String medId = '']) {
    audit.insert(
      0,
      AuditEntry(
        ts: DateTime.now().millisecondsSinceEpoch,
        user: who,
        type: type,
        action: action,
        detail: detail,
        role: role.key,
        amount: amount,
        ref: ref,
        medId: medId,
      ),
    );
    if (!online) pending++;
  }

  // ---- inventory screen state ---------------------------------------------
  String invQuery = '';
  String invCategory = 'all'; // 'all' or a category key
  String invFilter = 'all'; // all | low | out | soon | expired | need
  String invSort = 'name'; // name | stock | expiry | risk
  String invSupplier = 'all';
  String invType = 'all'; // all | otc | rx | ctrl

  void setInvQuery(String q) {
    invQuery = q;
    _touch();
  }

  void setInvFilter(String f) {
    invFilter = f;
    _touch();
  }

  void setInvCategory(String c) {
    invCategory = c;
    _touch();
  }

  void setInvSort(String s) {
    invSort = s;
    _touch();
  }

  /// Opens Inventory with a filter preselected (home tiles: goflt).
  void goInventoryFiltered(String filter) {
    invFilter = filter;
    invCategory = 'all';
    invQuery = '';
    goTab('inventory');
  }

  // ---- sales counter ------------------------------------------------------
  final List<CartLine> cart = [];
  String cartQuery = '';
  String salesTab = 'new'; // new | today
  String payMethod = 'cash';
  bool splitPayment = false;
  final Map<String, String> split = {
    'cash': '',
    'mobile': '',
    'bank': '',
    'credit': ''
  };
  String cartCustomerId = '';

  void setCartQuery(String q) {
    cartQuery = q;
    _touch();
  }

  void setSalesTab(String t) {
    salesTab = t;
    _touch();
  }

  void addToCart(Medicine m) {
    final i = cart.indexWhere((l) => l.medId == m.id);
    if (i >= 0) {
      cart[i].qty++;
    } else {
      cart.add(CartLine(m.id, 1));
    }
    cartQuery = '';
    _touch();
  }

  void changeCartQty(String medId, int delta) {
    final i = cart.indexWhere((l) => l.medId == medId);
    if (i < 0) return;
    cart[i].qty += delta;
    if (cart[i].qty <= 0) cart.removeAt(i);
    _touch();
  }

  void removeFromCart(String medId) {
    cart.removeWhere((l) => l.medId == medId);
    _touch();
  }

  void setPayMethod(String m) {
    payMethod = m;
    _touch();
  }

  void setSplitMode(bool on) {
    splitPayment = on;
    if (on) {
      split
        ..['cash'] = cartTotal.toString()
        ..['mobile'] = ''
        ..['bank'] = ''
        ..['credit'] = '';
    }
    _touch();
  }

  void setSplitAmount(String method, String v) {
    split[method] = v;
    _touch();
  }

  void setCartCustomer(String id) {
    cartCustomerId = id;
    _touch();
  }

  double get cartGross {
    var g = 0.0;
    for (final l in cart) {
      final m = medById(l.medId);
      if (m != null) g += l.qty * m.price;
    }
    return g;
  }

  /// Total after discount. Discount is not ported yet (see PORTING_MAP.md).
  double get cartTotal => AppFormat.r2(cartGross);

  /// payState(total): the payment parts and what is still unassigned.
  ({List<PaymentPart> parts, double remaining}) get payState {
    final total = cartTotal;
    if (!splitPayment) {
      return (parts: [PaymentPart(payMethod, total)], remaining: 0);
    }
    final parts = <PaymentPart>[];
    for (final key in const ['cash', 'mobile', 'bank', 'credit']) {
      final a = AppFormat.r2(double.tryParse(split[key] ?? '') ?? 0);
      if (a > 0) parts.add(PaymentPart(key, a));
    }
    final sum = parts.fold<double>(0, (s, p) => s + p.amount);
    return (parts: parts, remaining: AppFormat.r2(total - sum));
  }

  /// A cart line can be sold when the batches can cover its quantity.
  bool get cartIsSellable =>
      cart.isNotEmpty &&
      cart.every((l) {
        final m = medById(l.medId);
        return m != null && rules.alloc(m, l.qty) != null;
      });

  bool get canCheckout =>
      cartIsSellable &&
      payState.remaining == 0 &&
      (!payState.parts.any((p) => p.method == 'credit') ||
          cartCustomerId.isNotEmpty);

  /// finalizeSale() in the HTML (simplified: no Rx form and no discount yet).
  /// Takes stock first-expiry-first-out, writes sale lines, receipt number,
  /// payment parts, credit ledger and audit entries. Returns the sale id.
  String? checkout() {
    if (!canCheckout) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sid = 'S-${uid()}';
    final ps = payState;
    final creditPart = ps.parts.where((p) => p.method == 'credit');
    final customer = creditPart.isNotEmpty
        ? customers.firstWhere((c) => c.id == cartCustomerId)
        : null;
    receiptNo[sid] = nextNo('RC', 5, receiptNo.values);
    lastSaleId = sid;
    var total = 0.0;
    for (final l in cart) {
      final m = medById(l.medId)!;
      final a = rules.alloc(m, l.qty)!;
      for (final x in a) {
        x.batch.qty -= x.take;
      }
      final amt = l.qty * m.price;
      total += amt;
      final unitCost = a.fold<double>(
              0, (s, x) => s + x.take * rules.batchCost(m, x.batch)) /
          l.qty;
      sales.add(SaleLine(
        lid: uid(),
        saleId: sid,
        ts: now,
        medId: m.id,
        qty: l.qty,
        price: m.price,
        cost: unitCost,
        listPrice: m.price,
        customerId: customer?.id,
        by: who,
        batches: a.map((x) => BatchTake(x.batch.no, x.take)).toList(),
      ));
      m.ledger.add(StockEntry(
        id: uid(),
        ts: now,
        type: 'sold',
        q: -l.qty,
        by: who,
        ref: receiptNo[sid]!,
      ));
      log(
          'sale',
          'Sold ${l.qty} × ${m.name}',
          '${AppFormat.etb(amt)}, batch ${a.map((x) => x.batch.no).join(', ')}',
          amt,
          receiptNo[sid]!,
          m.id);
    }
    payments[sid] = ps.parts;
    log(
        'sale',
        'Payment ${AppFormat.etb(total)}',
        ps.parts
            .map((p) => '${tPay(p.method)} ${AppFormat.etb(p.amount)}')
            .join(' + '));
    if (customer != null) {
      final cr = creditPart.first;
      customer.tx.add(CreditTx(
        id: uid(),
        ts: now,
        type: 'sale',
        amount: cr.amount,
        saleId: sid,
        note:
            cart.map((l) => '${l.qty} × ${medById(l.medId)!.name}').join(', '),
      ));
      log('credit',
          'Credit sale ${AppFormat.etb(cr.amount)} to ${customer.name}');
    }
    cart.clear();
    cartCustomerId = '';
    payMethod = 'cash';
    splitPayment = false;
    _touch();
    return sid;
  }

  /// Payment method label in the current language (payName()).
  String tPay(String key) {
    const en = {
      'cash': 'Cash',
      'mobile': 'Mobile money',
      'bank': 'Bank',
      'credit': 'On credit'
    };
    return t(en[key] ?? key);
  }

  // ---- stock actions (home attention rows, medicine page) -----------------
  /// Writes an expired batch off. Needs pharmacist or owner; controlled
  /// medicines only by the owner (woSheet rules in the HTML).
  String? writeOffBatch(Medicine m, String batchNo) {
    if (!canEdit) return 'Only a pharmacist or the owner can write off stock.';
    if (m.type == MedType.ctrl && role != UserRole.owner) {
      return 'Controlled stock can only be changed by the owner. Use Stocktake and the owner approves it.';
    }
    final i = m.batches.indexWhere(
        (b) => b.no == batchNo && b.qty > 0 && AppFormat.daysTo(b.exp) < 0);
    if (i < 0) return 'This batch is no longer expired stock.';
    final b = m.batches[i];
    final loss = b.qty * rules.batchCost(m, b);
    m.ledger.add(StockEntry(
      id: uid(),
      ts: DateTime.now().millisecondsSinceEpoch,
      type: 'written',
      q: -b.qty,
      by: who,
      ref: b.no,
      why: 'Expired',
    ));
    log('stock', 'Wrote off ${b.qty} × ${m.name}',
        'Batch ${b.no} expired · loss ${AppFormat.etb(loss)}', loss, '', m.id);
    b.qty = 0;
    _touch();
    return null;
  }

  /// Saves a new product together with its first batch (`saveMed()` in HTML).
  /// The form has already applied the duplicate and validation rules before it
  /// reaches this state boundary.
  Medicine registerMedicine({
    required String name,
    required String generic,
    required List<String> aliases,
    required String barcode,
    required String category,
    required MedType type,
    required String form,
    required String strength,
    required String manufacturer,
    required double price,
    required double cost,
    required int reorder,
    required bool autoPlan,
    required String supplierId,
    required String batchNo,
    required String expiry,
    required int quantity,
  }) {
    final duplicate = findMedicineDuplicate(
      meds,
      name: name,
      barcode: barcode,
      form: form,
      strength: strength,
    );
    if (duplicate.byBarcode != null) {
      throw StateError('This barcode is already registered');
    }
    final medicine = Medicine(
      id: 'm-${uid()}',
      name: name,
      generic: generic.isEmpty ? name : generic,
      aka: aliases,
      barcode: barcode,
      category: category,
      type: type,
      form: form,
      strength: strength,
      manufacturer: manufacturer,
      price: price,
      cost: cost,
      reorder: reorder,
      autoPlan: autoPlan,
      supplierId: supplierId,
      batches: [Batch(no: batchNo, exp: expiry, qty: quantity, cost: cost)],
    );
    medicine.ledger.add(StockEntry(
      id: uid(),
      ts: DateTime.now().millisecondsSinceEpoch,
      type: 'received',
      q: quantity,
      by: who,
      ref: batchNo,
      why: 'First batch',
    ));
    meds.add(medicine);
    log(
      'stock',
      'Registered $name',
      'Batch $batchNo · $quantity units · exp ${AppFormat.fmtD(expiry)} · ${type.label}',
      quantity * cost,
      '',
      medicine.id,
    );
    _touch();
    return medicine;
  }

  /// Preserves an audit trail for the simulated chat, like `accessLog()` in
  /// the HTML preview.
  void recordChatQuestion(String question) {
    log(
      'access',
      'AI chat question',
      question.length > 60 ? '${question.substring(0, 60)}…' : question,
    );
    _touch();
  }

  /// Adds [qty] units of [m] to the supplier's draft order (creates it if needed).
  PurchaseOrder createOrderLine(Medicine m, int qty) {
    var po = orders
        .where((o) => o.supplierId == m.supplierId && o.status == 'draft')
        .firstOrNull;
    if (po == null) {
      po = PurchaseOrder(
        id: SeedData.poId(orders.length + 1),
        supplierId: m.supplierId,
        ts: DateTime.now().millisecondsSinceEpoch,
        status: 'draft',
        lines: [],
      );
      orders.add(po);
    }
    final l = po.lines.where((x) => x.medId == m.id).firstOrNull;
    if (l != null) {
      l.qty += qty;
    } else {
      po.lines.add(PoLine(medId: m.id, qty: qty, cost: m.cost));
    }
    log('order', 'Added ${m.name} × $qty to order ${po.id}',
        supplierOf(m.supplierId).name, qty * m.cost, po.id, m.id);
    _touch();
    return po;
  }

  /// Customer pays part of their debt (payment sheet on the Credit screen).
  void recordPayment(Customer c, double amount, String method) {
    if (amount <= 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    c.tx.add(CreditTx(
      id: uid(),
      ts: now,
      type: 'pay',
      amount: amount,
      note: method == 'bank'
          ? 'Bank transfer'
          : method == 'mobile'
              ? 'Mobile money'
              : 'Cash',
      method: method,
    ));
    log(
        'credit',
        'Payment ${AppFormat.etb(amount)} from ${c.name}',
        method == 'bank'
            ? 'Bank'
            : method == 'mobile'
                ? 'Mobile money'
                : 'Cash',
        amount);
    _touch();
  }

  void setAlertDays(int d) {
    alertDays = d < 1 ? 1 : d;
    _touch();
  }

  // ---- report settings ----------------------------------------------------
  /// Persists the simulated monthly-report destination and schedule. The real
  /// server worker will consume this setting later; keeping it in AppState
  /// makes the screen offline-first today.
  void saveMonthlyReportSettings({
    required bool enabled,
    required String telegram,
    required String accountantEmail,
    required int day,
  }) {
    final next = MonthlyReportSettings(
      enabled: enabled,
      telegram: telegram.trim(),
      accountantEmail: accountantEmail.trim(),
      day: day.clamp(1, 28).toInt(),
      lastSentMonth: monthlyReport.lastSentMonth,
    );
    if (next.enabled != monthlyReport.enabled ||
        next.telegram != monthlyReport.telegram ||
        next.accountantEmail != monthlyReport.accountantEmail ||
        next.day != monthlyReport.day) {
      monthlyReport = next;
      log('report', 'Monthly report settings saved',
          '${next.enabled ? 'On' : 'Off'} · day ${next.day}');
      _touch();
    }
  }

  /// Records the simulated server delivery. A return value lets the UI show a
  /// precise, translated confirmation without duplicating the data mutation.
  bool sendMonthlyReportNow(String monthKey) {
    if (!monthlyReport.hasRecipient) return false;
    final parts = monthKey.split('-').map(int.parse).toList();
    final range = ReportDateRange(
      DateTime(parts[0], parts[1]),
      DateTime(parts[0], parts[1] + 1),
    );
    final lines = sales.where((line) => range.includes(line.ts)).toList();
    final summary = ReportingRules.salesSummary(lines, range);
    final receipts = <String, List<SaleLine>>{};
    for (final line in lines) {
      (receipts[line.saleId] ??= []).add(line);
    }
    final paidByMethod = <String, double>{};
    for (final entry in receipts.entries) {
      final amount =
          entry.value.fold<double>(0, (sum, line) => sum + line.revenue);
      for (final payment
          in payments[entry.key] ?? [PaymentPart('cash', amount)]) {
        paidByMethod[payment.method] =
            (paidByMethod[payment.method] ?? 0) + payment.amount;
      }
    }
    final paymentSummary = paidByMethod.entries
        .map((entry) => '${tPay(entry.key)} ${AppFormat.etb(entry.value)}')
        .join(' · ');
    final destinations = [
      if (monthlyReport.telegram.isNotEmpty)
        'Telegram ${monthlyReport.telegram}',
      if (monthlyReport.accountantEmail.isNotEmpty)
        monthlyReport.accountantEmail,
    ].join(', ');
    monthlyReport = monthlyReport.copyWith(lastSentMonth: monthKey);
    log('report', 'Monthly report sent (simulated)',
        '$monthKey · Sales ${AppFormat.etb(summary.revenue)} · Profit ${AppFormat.etb(summary.profit)} · Payments $paymentSummary · to $destinations');
    _touch();
    return true;
  }

  void setTaxRateInPrices(double rate) {
    final double next = rate < 0 ? 0 : rate;
    if (next == taxRateInPrices) return;
    taxRateInPrices = next;
    log('report', 'Tax rate changed', '$next% included in prices');
    _touch();
  }

  void recordReportExport(String title, String format, String range) {
    log('report', 'Exported $title as $format', range);
    _touch();
  }

  void recordReportShare(String title, String range) {
    log('report', 'Shared $title', range);
    _touch();
  }

  /// Preview only: switch role to test what each role can see.
  void setRole(UserRole r) {
    role = r;
    if (!can(Perm.ops) && stack.isNotEmpty) {
      stack
        ..clear()
        ..add(const NavEntry('home'));
    }
    _touch();
  }

  // ---- queries used by several screens ------------------------------------
  List<SaleLine> salesOn(String isoDay) =>
      sales.where((s) => AppFormat.dayKey(s.ts) == isoDay).toList();

  /// Seven daily revenue totals ending today (week() in the HTML).
  List<double> weekRevenue() => List.generate(7, (i) {
        final k = AppFormat.iso(AppFormat.addDays(i - 6));
        return salesOn(k).fold<double>(0, (a, s) => a + s.revenue);
      });

  /// Money collected today split by method (todayMoney()).
  ({
    double cash,
    double mobile,
    double bank,
    double credit,
    double collected,
    double drawer
  }) todayMoney() {
    final k = AppFormat.iso(AppFormat.today);
    var cash = 0.0, mobile = 0.0, bank = 0.0, credit = 0.0;
    final seen = <String>{};
    for (final s in salesOn(k)) {
      if (!seen.add(s.saleId)) continue;
      final lines = sales.where((x) => x.saleId == s.saleId);
      final parts = payments[s.saleId] ??
          [
            PaymentPart(s.customerId != null ? 'credit' : 'cash',
                lines.fold<double>(0, (a, x) => a + x.revenue))
          ];
      for (final p in parts) {
        switch (p.method) {
          case 'cash':
            cash += p.amount;
          case 'mobile':
            mobile += p.amount;
          case 'bank':
            bank += p.amount;
          case 'credit':
            credit += p.amount;
        }
      }
    }
    var collected = 0.0;
    for (final c in customers) {
      for (final x in c.tx) {
        if (AppFormat.dayKey(x.ts) == k && x.method == 'cash') {
          collected += x.type == 'pay'
              ? x.amount
              : x.type == 'rev'
                  ? -x.amount
                  : 0;
        }
      }
    }
    return (
      cash: cash,
      mobile: mobile,
      bank: bank,
      credit: credit,
      collected: collected,
      drawer: cash + collected
    );
  }
}
