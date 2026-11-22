import '../../core/utils/app_format.dart';
import '../models/audit_entry.dart';
import '../models/customer.dart';
import '../models/medicine.dart';
import '../models/purchase_order.dart';
import '../models/reporting_models.dart';
import '../models/sale.dart';
import '../models/supplier.dart';

const int _day = 86400000;

/// Deterministic sample data, ported from the HTML (SUPS, MEDS, seedSales,
/// buildHistory, histOrders, seedCust, seedAudit). Used until the real
/// database is connected. Remove when the Hive/Firestore repository is ready.
class SeedData {
  SeedData._();

  // ---- tiny seeded random generators (Park-Miller, same as the HTML) ------
  static int _s = 11;
  static double _rnd() {
    _s = (_s * 16807) % 2147483647;
    return _s / 2147483647;
  }

  static String barcode() =>
      (6000000000000 + (_rnd() * 1000000000000).floor()).toString();

  static const List<Supplier> suppliers = [
    Supplier(
        id: 's1',
        name: 'Addis Pharma Supply',
        phone: '0911 000 111',
        termsDays: 15,
        leadDays: 4),
    Supplier(
        id: 's2',
        name: 'EPHARM',
        phone: '0911 222 333',
        termsDays: 30,
        leadDays: 3),
    Supplier(
        id: 's3',
        name: 'Julphar Ethiopia',
        phone: '0911 444 555',
        termsDays: 0,
        leadDays: 5),
  ];

  static String _d(int n) => AppFormat.iso(AppFormat.addDays(n));

  static List<Medicine> medicines() => _withSeedLedger([
        Medicine(
            id: 'm1',
            aka: ['Tylenol', 'Acetaminophen', 'Para', 'ፓራሲታሞል'],
            name: 'Paracetamol 500mg',
            generic: 'Paracetamol',
            barcode: '6291041500213',
            category: 'pain',
            type: MedType.otc,
            price: 5,
            cost: 3.2,
            reorder: 50,
            supplierId: 's2',
            form: 'tab',
            strength: '500mg',
            batches: [
              Batch(no: 'B101', exp: _d(40), qty: 30),
              Batch(no: 'B102', exp: _d(420), qty: 150)
            ]),
        Medicine(
            id: 'm2',
            aka: ['Paracetamol', 'ፓናዶል'],
            name: 'Panadol 500mg',
            generic: 'Paracetamol',
            barcode: '5000158100000',
            category: 'pain',
            type: MedType.otc,
            price: 7,
            cost: 4.8,
            reorder: 40,
            supplierId: 's1',
            form: 'tab',
            strength: '500mg',
            batches: [Batch(no: 'P220', exp: _d(300), qty: 0)]),
        Medicine(
            id: 'm3',
            aka: ['Amox', 'አሞክሲሲሊን'],
            name: 'Amoxicillin 500mg',
            generic: 'Amoxicillin',
            barcode: '6291041500777',
            category: 'abx',
            type: MedType.rx,
            price: 12,
            cost: 8,
            reorder: 60,
            supplierId: 's2',
            form: 'cap',
            strength: '500mg',
            batches: [
              Batch(no: 'A55', exp: _d(25), qty: 20),
              Batch(no: 'A56', exp: _d(500), qty: 45)
            ]),
        Medicine(
            id: 'm4',
            aka: ['Amoxicillin'],
            name: 'Amoxil 500mg',
            generic: 'Amoxicillin',
            barcode: '5012345678900',
            category: 'abx',
            type: MedType.rx,
            price: 15,
            cost: 10.5,
            reorder: 30,
            supplierId: 's1',
            form: 'cap',
            strength: '500mg',
            batches: [Batch(no: 'X12', exp: _d(250), qty: 40)]),
        Medicine(
            id: 'm5',
            aka: ['Brufen', 'Advil', 'Nurofen', 'ኢቡፕሮፌን'],
            name: 'Ibuprofen 400mg',
            generic: 'Ibuprofen',
            barcode: '6291041500555',
            category: 'pain',
            type: MedType.otc,
            price: 8,
            cost: 5,
            reorder: 40,
            supplierId: 's3',
            form: 'tab',
            strength: '400mg',
            batches: [
              Batch(no: 'I77', exp: _d(-10), qty: 15),
              Batch(no: 'I78', exp: _d(365), qty: 100)
            ]),
        Medicine(
            id: 'm6',
            aka: ['Ascorbic acid', 'Cevit', 'ቫይታሚን ሲ'],
            name: 'Vitamin C 1000mg',
            generic: 'Ascorbic acid',
            barcode: '6291041500999',
            category: 'vit',
            type: MedType.otc,
            price: 10,
            cost: 6.5,
            reorder: 30,
            supplierId: 's1',
            form: 'tab',
            strength: '1000mg',
            batches: [Batch(no: 'V1', exp: _d(180), qty: 12)]),
        Medicine(
            id: 'm7',
            aka: ['Glucophage', 'ሜትፎርሚን'],
            name: 'Metformin 500mg',
            generic: 'Metformin',
            barcode: '6291041500321',
            category: 'diab',
            type: MedType.rx,
            price: 4,
            cost: 2.4,
            reorder: 100,
            supplierId: 's2',
            form: 'tab',
            strength: '500mg',
            batches: [Batch(no: 'M9', exp: _d(600), qty: 300)]),
        Medicine(
            id: 'm8',
            aka: ['Tramal'],
            name: 'Tramadol 50mg',
            generic: 'Tramadol',
            barcode: '6291041500444',
            category: 'pain',
            type: MedType.ctrl,
            price: 20,
            cost: 14,
            reorder: 20,
            supplierId: 's3',
            form: 'cap',
            strength: '50mg',
            batches: [Batch(no: 'T3', exp: _d(200), qty: 35)]),
        Medicine(
            id: 'm9',
            aka: ['Tussin', 'ሳል መድኃኒት'],
            name: 'Cough Syrup 100ml',
            generic: 'Dextromethorphan',
            barcode: '6291041500888',
            category: 'cold',
            type: MedType.otc,
            price: 45,
            cost: 31,
            reorder: 15,
            supplierId: 's1',
            form: 'syr',
            strength: '100ml',
            batches: [Batch(no: 'C4', exp: _d(15), qty: 22)]),
        Medicine(
            id: 'm10',
            aka: ['Oral rehydration', 'ኦአርኤስ'],
            name: 'ORS Sachet',
            generic: 'Oral rehydration salts',
            barcode: '6291041500111',
            category: 'dig',
            type: MedType.otc,
            price: 3,
            cost: 1.8,
            reorder: 50,
            supplierId: 's2',
            form: 'sach',
            strength: '',
            batches: [Batch(no: 'O1', exp: _d(700), qty: 200)]),
        Medicine(
            id: 'm11',
            aka: ['Losec', 'Prilosec', 'ኦሜፕራዞል'],
            name: 'Omeprazole 20mg',
            generic: 'Omeprazole',
            barcode: '6291041500666',
            category: 'dig',
            type: MedType.otc,
            price: 6,
            cost: 3.9,
            reorder: 40,
            supplierId: 's3',
            form: 'cap',
            strength: '20mg',
            batches: [Batch(no: 'OM2', exp: _d(365), qty: 90)]),
        Medicine(
            id: 'm12',
            aka: ['Zithromax', 'Azithro', 'አዚትሮማይሲን'],
            name: 'Azithromycin 500mg',
            generic: 'Azithromycin',
            barcode: '6291041500222',
            category: 'abx',
            type: MedType.rx,
            price: 40,
            cost: 28,
            reorder: 20,
            supplierId: 's2',
            form: 'tab',
            strength: '500mg',
            batches: [Batch(no: 'Z9', exp: _d(400), qty: 8)]),
      ]);

  /// A handful of real-looking stock events make the Movements and Losses
  /// reports useful before the stocktake and receiving modules are ported.
  /// They are audit history only; the batch quantities above remain the
  /// current on-shelf snapshot.
  static List<Medicine> _withSeedLedger(List<Medicine> medicines) {
    Medicine med(String id) => medicines.firstWhere((m) => m.id == id);
    final now = DateTime.now().millisecondsSinceEpoch;
    med('m3').ledger.addAll([
      StockEntry(
        id: 'seed-led-1',
        ts: now - 12 * _day,
        type: 'received',
        q: 80,
        by: 'Meron (Admin)',
        ref: 'A56',
        invoice: 'EP-20418',
      ),
      StockEntry(
        id: 'seed-led-2',
        ts: now - 5 * _day,
        type: 'sold',
        q: -14,
        by: 'Selam (Pharmacist)',
        ref: 'RL-00004',
      ),
    ]);
    med('m5').ledger.add(StockEntry(
          id: 'seed-led-3',
          ts: now - 10 * _day,
          type: 'written',
          q: -6,
          by: 'Selam (Pharmacist)',
          ref: 'I77',
          why: 'Expired',
        ));
    med('m8').ledger.addAll([
      StockEntry(
        id: 'seed-led-4',
        ts: now - 6 * _day,
        type: 'sold',
        q: -10,
        by: 'Selam (Pharmacist)',
        ref: 'RL-00002',
      ),
      StockEntry(
        id: 'seed-led-5',
        ts: now - 1 * _day,
        type: 'adjusted',
        q: -1,
        by: 'Meron (Admin)',
        ref: 'ST-0003',
        why: 'Damaged pack',
      ),
    ]);
    return medicines;
  }

  /// The same five sample records shown in the reference report. Their dates
  /// are deliberately fixed so the report is stable in demos and tests.
  static List<RxRegisterEntry> rxRegister() => [
        RxRegisterEntry(
          sequence: 5,
          ts: DateTime(2026, 11, 21, 16).millisecondsSinceEpoch,
          medicineId: 'm8',
          qty: 10,
          patient: 'Yonas Alemu',
          rxNo: 'RX-20418',
          doctor: 'Dr. Mekonnen T.',
          controlled: true,
          by: 'Selam (Pharmacist)',
        ),
        RxRegisterEntry(
          sequence: 4,
          ts: DateTime(2026, 11, 20, 13).millisecondsSinceEpoch,
          medicineId: 'm3',
          qty: 14,
          patient: 'Selamawit G.',
          rxNo: 'RX-20417',
          doctor: 'Dr. Hanna A.',
          controlled: false,
          by: 'Selam (Pharmacist)',
        ),
        RxRegisterEntry(
          sequence: 3,
          ts: DateTime(2026, 11, 19, 11).millisecondsSinceEpoch,
          medicineId: 'm12',
          qty: 6,
          patient: 'Bereket L.',
          rxNo: 'RX-20391',
          doctor: 'Dr. Mekonnen T.',
          controlled: false,
          by: 'Meron (Admin)',
        ),
        RxRegisterEntry(
          sequence: 2,
          ts: DateTime(2026, 11, 15, 10).millisecondsSinceEpoch,
          medicineId: 'm8',
          qty: 10,
          patient: 'Aster D.',
          rxNo: 'RX-20350',
          doctor: 'Dr. Fikru B.',
          controlled: true,
          by: 'Selam (Pharmacist)',
        ),
        RxRegisterEntry(
          sequence: 1,
          ts: DateTime(2026, 11, 10, 9).millisecondsSinceEpoch,
          medicineId: 'm7',
          qty: 60,
          patient: 'Tigist Bekele',
          rxNo: 'RX-20301',
          doctor: 'Dr. Hanna A.',
          controlled: false,
          by: 'Selam (Pharmacist)',
        ),
      ];

  static List<SupplierInvoice> supplierInvoices() {
    String d(int days) => AppFormat.iso(AppFormat.addDays(days));
    int ts(int days) => AppFormat.addDays(days).millisecondsSinceEpoch;
    return [
      SupplierInvoice(
        id: 'B-1',
        supplierId: 's2',
        invoiceNo: 'EP-20418',
        receivedTs: ts(-12),
        dueDate: d(18),
        amount: 25000,
      ),
      SupplierInvoice(
        id: 'B-2',
        supplierId: 's1',
        invoiceNo: 'APS-3307',
        receivedTs: ts(-40),
        dueDate: d(-25),
        amount: 8400,
        payments: [SupplierPayment(ts: ts(-20), amount: 2000, method: 'bank')],
      ),
      SupplierInvoice(
        id: 'B-3',
        supplierId: 's3',
        invoiceNo: 'JE-1182',
        receivedTs: ts(-4),
        dueDate: d(3),
        amount: 3600,
      ),
      SupplierInvoice(
        id: 'B-4',
        supplierId: 's3',
        invoiceNo: 'JE-1099',
        receivedTs: ts(-35),
        dueDate: d(-30),
        amount: 5200,
        payments: [SupplierPayment(ts: ts(-33), amount: 5200, method: 'cash')],
      ),
    ];
  }

  static List<MissedSale> missedSales() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      MissedSale(
          id: 'MS-0001',
          ts: now - 2 * _day,
          medicineName: 'Panadol 500mg',
          qty: 2,
          reason: 'Out of stock',
          by: 'Meron (Admin)'),
      MissedSale(
          id: 'MS-0002',
          ts: now - 7 * _day,
          medicineName: 'Ceftriaxone injection',
          qty: 1,
          reason: 'Not registered',
          by: 'Selam (Pharmacist)'),
      MissedSale(
          id: 'MS-0003',
          ts: now - 16 * _day,
          medicineName: 'Azithromycin 500mg',
          qty: 6,
          reason: 'Low stock',
          by: 'Selam (Pharmacist)'),
    ];
  }

  /// Matches the two-month expense demo in the HTML finance report.
  static List<ExpenseEntry> expenses() {
    final now = DateTime.now();
    const sample = [
      ('Rent', 15000.0),
      ('Salary', 20000.0),
      ('Electricity', 1800.0),
      ('Transport', 900.0),
    ];
    return [
      for (var monthOffset = -1; monthOffset <= 0; monthOffset++)
        for (var i = 0; i < sample.length; i++)
          ExpenseEntry(
            id: 'expense-$monthOffset-$i',
            ts: DateTime(now.year, now.month + monthOffset, 1, 9)
                .millisecondsSinceEpoch,
            category: sample[i].$1,
            amount: sample[i].$2,
            by: 'Selam',
          ),
    ];
  }

  // ---- two years of history so Month / Year views have data ---------------
  static double _pf(int yb) => const [1.0, 0.9, 0.8].elementAtOrNull(yb) ?? 0.8;

  static List<SaleLine>? _histSales;
  static Map<String, List<CreditTx>>? _histTx;
  static List<PurchaseOrder> _histOrdersCache = [];

  static void _buildHistory(List<Medicine> meds) {
    var sd = 20260;
    double r() {
      sd = (sd * 16807) % 2147483647;
      return sd / 2147483647;
    }

    final today = AppFormat.today;
    final cy = today.year;
    final start = DateTime(cy - 2, 1, 1);
    final span = (today.difference(start).inHours / 24).round();
    final sales = <SaleLine>[];
    final tx = <String, List<CreditTx>>{};
    const rate = {
      'm1': .8,
      'm3': .6,
      'm5': .6,
      'm6': .45,
      'm9': .5,
      'm10': .55,
      'm4': .25,
      'm12': .2,
      'm8': .1
    };
    const slow = {'m7': .35, 'm11': .3, 'm2': .3};
    var n = 0;
    for (var d = 30; d <= span; d++) {
      final dt = AppFormat.addDays(-d);
      final yb = cy - dt.year;
      final mo = dt.month - 1; // JS getMonth()
      final g = const [1.0, .82, .66].elementAtOrNull(yb) ?? .66;
      final wd = dt.weekday == DateTime.sunday ? .6 : 1.0;
      final ids = [...rate.keys, if (d >= 100) ...slow.keys];
      for (final id in ids) {
        final m = meds.firstWhere((x) => x.id == id);
        final base = rate[id] ?? slow[id]!;
        final season = (id == 'm9' || id == 'm6')
            ? ([10, 11, 0, 1].contains(mo) ? 1.6 : .8)
            : id == 'm10'
                ? ([6, 7, 8].contains(mo) ? 1.4 : .9)
                : 1.0;
        final p = base * g * wd * season;
        if (r() < (p > .95 ? .95 : p)) {
          final q = 1 + (r() * ((id == 'm10' || id == 'm1') ? 8 : 4)).floor();
          final hour = 8 + (r() * 11).floor();
          final price = ((m.price * _pf(yb) * 2).round() / 2);
          final cost = (m.cost * _pf(yb) * 10).round() / 10;
          sales.add(SaleLine(
            lid: 'H${n++}',
            saleId: 'HS$n',
            ts: dt.millisecondsSinceEpoch + hour * 3600000,
            medId: id,
            qty: q,
            price: price < 1 ? 1.0 : price,
            cost: cost,
          ));
        }
      }
    }
    const notes = [
      'Monthly medicines',
      'Antibiotic course',
      'Vitamins and cold remedies',
      'Diabetes supply',
      'Pain relief and ORS'
    ];
    for (final id in ['c1', 'c2', 'c3', 'c4']) {
      final list = <CreditTx>[];
      const cnt = 12;
      final from = start.millisecondsSinceEpoch + 10 * _day;
      final to = DateTime.now().millisecondsSinceEpoch - 45 * _day;
      final sg = (to - from) / cnt;
      for (var i = 0; i < cnt; i++) {
        final t = from + sg * i + r() * sg * .8;
        final amt = ((60 + r() * 640) / 10).round() * 10;
        final pay = t + (7 + (r() * 24).floor()) * _day;
        final note = notes[(r() * notes.length).floor()];
        final method = r() < .7 ? 'Cash' : 'Bank transfer';
        list.add(CreditTx(
            id: '$id-h${i}s',
            ts: t.round(),
            type: 'sale',
            amount: amt.toDouble(),
            note: note));
        list.add(CreditTx(
            id: '$id-h${i}p',
            ts: pay.round(),
            type: 'pay',
            amount: amt.toDouble(),
            note: method,
            method: method.startsWith('Bank') ? 'bank' : 'cash'));
      }
      tx[id] = list;
    }
    _histSales = sales;
    _histTx = tx;
  }

  static int _todayTs(double u) {
    final o = AppFormat.today.millisecondsSinceEpoch + 8 * 3600000;
    final n = DateTime.now().millisecondsSinceEpoch;
    return n > o + 3600000 ? o + (u * (n - o)).floor() : n - (u * 3e6).floor();
  }

  static List<SaleLine> sales(List<Medicine> meds) {
    _buildHistory(meds);
    final out = <SaleLine>[];
    const fast = {
      'm1': .8,
      'm3': .6,
      'm5': .6,
      'm6': .45,
      'm9': .5,
      'm10': .55,
      'm4': .25,
      'm12': .2,
      'm8': .1
    };
    var n = 0;
    for (var d = 0; d < 30; d++) {
      for (final id in fast.keys) {
        final force = d == 0 && (id == 'm1' || id == 'm3');
        if (_rnd() < fast[id]! || force) {
          final m = meds.firstWhere((x) => x.id == id);
          final q =
              (1 + (_rnd() * ((id == 'm10' || id == 'm1') ? 8 : 4)).floor()) *
                  (id == 'm6' ? 3 : 1);
          final ts = d == 0
              ? _todayTs(_rnd())
              : AppFormat.addDays(-d).millisecondsSinceEpoch +
                  (9 + (_rnd() * 9).floor()) * 3600000;
          out.add(SaleLine(
              lid: 'L${n++}',
              saleId: 'L$n',
              ts: ts,
              medId: id,
              qty: q,
              price: m.price,
              cost: m.cost));
        }
      }
    }
    for (final x in const [
      ['m7', 75, 10],
      ['m11', 92, 5],
      ['m2', 40, 20]
    ]) {
      final m = meds.firstWhere((y) => y.id == x[0]);
      out.add(SaleLine(
          lid: 'L${n++}',
          saleId: 'L$n',
          ts: AppFormat.addDays(-(x[1] as int)).millisecondsSinceEpoch +
              36000000,
          medId: x[0] as String,
          qty: x[2] as int,
          price: m.price,
          cost: m.cost));
    }
    final all = [..._histSales!, ...out];
    _histOrdersCache = _histOrders(all, meds);
    return all;
  }

  static String poId(int n) => 'PO-${n.toString().padLeft(4, '0')}';

  static List<PurchaseOrder> _histOrders(
      List<SaleLine> all, List<Medicine> meds) {
    var sd = 7771;
    double r() {
      sd = (sd * 16807) % 2147483647;
      return sd / 2147483647;
    }

    final cy = AppFormat.today.year;
    final by = <String, _Bucket>{};
    for (final x in all) {
      final d = DateTime.fromMillisecondsSinceEpoch(x.ts);
      final mk = d.year * 12 + (d.month - 1);
      final m = meds.firstWhere((e) => e.id == x.medId);
      final k = '$mk|${m.supplierId}';
      final o = by.putIfAbsent(k, () => _Bucket(mk, m.supplierId));
      o.units[x.medId] = (o.units[x.medId] ?? 0) + x.qty;
    }
    final list = by.values.toList()
      ..sort((a, b) => a.mk != b.mk ? a.mk - b.mk : a.sup.compareTo(b.sup));
    final out = <PurchaseOrder>[];
    for (final o in list) {
      final yr = o.mk ~/ 12;
      final mo = o.mk % 12;
      final yb = cy - yr;
      final ts =
          DateTime(yr, mo + 1, 3 + (r() * 22).floor(), 9 + (r() * 8).floor())
              .millisecondsSinceEpoch;
      if (r() < .12 || ts > DateTime.now().millisecondsSinceEpoch - 3 * _day) {
        continue;
      }
      out.add(PurchaseOrder(
        id: '',
        supplierId: o.sup,
        ts: ts,
        status: 'received',
        lines: o.units.keys.map((id) {
          final m = meds.firstWhere((e) => e.id == id);
          final qty = ((o.units[id]! * (.8 + r() * .5) / 10).round() * 10);
          return PoLine(
              medId: id,
              qty: qty < 10 ? 10 : qty,
              cost: (m.cost * _pf(yb) * 10).round() / 10);
        }).toList(),
      ));
    }
    out.sort((a, b) => a.ts.compareTo(b.ts));
    return [
      for (var i = 0; i < out.length; i++)
        PurchaseOrder(
            id: poId(i + 1),
            supplierId: out[i].supplierId,
            ts: out[i].ts,
            status: 'received',
            lines: out[i].lines),
    ];
  }

  static List<PurchaseOrder> orders() => [
        ..._histOrdersCache,
        PurchaseOrder(
          id: poId(_histOrdersCache.length + 1),
          supplierId: 's3',
          ts: DateTime.now().millisecondsSinceEpoch - 30 * 3600000,
          status: 'sent',
          lines: [PoLine(medId: 'm8', qty: 20, cost: 14)],
        ),
      ];

  static List<Customer> customers() {
    final n = DateTime.now().millisecondsSinceEpoch;
    Customer c(String id, String name, String phone, double? limit,
        List<CreditTx> tx) {
      final hist = _histTx?[id] ?? const <CreditTx>[];
      return Customer(
          id: id, name: name, phone: phone, limit: limit, tx: [...hist, ...tx]);
    }

    CreditTx tx(String id, int ts, String type, double amt, String note,
            {bool open = false, String method = ''}) =>
        CreditTx(
            id: id,
            ts: ts,
            type: type,
            amount: amt,
            note: note,
            opening: open,
            method: method);

    return [
      c('c1', 'Abebe Kebede', '0911 22 33 44', 3000, [
        tx('c1-a', n - 100 * _day, 'sale', 3000,
            'Monthly medicines (old balance)',
            open: true),
        tx('c1-b', n - 5 * _day, 'sale', 850,
            '10 × Amoxicillin 500mg + others'),
      ]),
      c('c2', 'Almaz Tesfaye', '0922 55 66 77', null, [
        tx('c2-a', n - 12 * _day, 'sale', 520, 'Metformin ×60, Vitamin C ×10'),
        tx('c2-b', n - 1 * _day, 'pay', 200, 'Cash', method: 'cash'),
      ]),
      c('c3', 'Tigist Bekele', '0933 11 22 33', 1500, [
        tx('c3-a', n - 20 * _day, 'sale', 1500, 'Monthly diabetes supply'),
        tx('c3-b', n - 8 * _day, 'pay', 300, 'Cash', method: 'cash'),
      ]),
      c('c4', 'Dawit Haile', '0944 88 99 00', null, [
        tx('c4-a', n - 9 * _day, 'sale', 200, 'Cough syrup ×4'),
        tx('c4-b', n - 7 * _day, 'pay', 200, 'Cash', method: 'cash'),
      ]),
      c('c5', 'Abebe Kebede', '0955 12 34 56', null, [
        tx('c5-a', n - 40 * _day, 'sale', 400, '5 × Vitamin C + cough syrup'),
      ]),
    ];
  }

  static List<AuditEntry> audit(String currentUser) {
    int mins(int n) => DateTime.now().millisecondsSinceEpoch - n * 60000;
    return [
      AuditEntry(
          ts: mins(12),
          user: currentUser,
          type: 'sale',
          action: 'Sold 3 × Paracetamol 500mg',
          detail: 'ETB 15 · B101'),
      AuditEntry(
          ts: mins(190),
          user: 'Meron (Admin)',
          type: 'stock',
          action: 'Added batch B102 to Paracetamol 500mg',
          detail: '150 units · exp in 420 days'),
      AuditEntry(
          ts: mins(26 * 60),
          user: currentUser,
          type: 'credit',
          action: 'Payment ETB 200 from Almaz Tesfaye',
          detail: 'Cash'),
      AuditEntry(
          ts: mins(30 * 60),
          user: 'Meron (Admin)',
          type: 'order',
          action:
              'Purchase order ${poId(_histOrdersCache.length + 1)} sent to Julphar Ethiopia',
          detail: '1 item'),
      AuditEntry(
          ts: mins(50 * 60),
          user: currentUser,
          type: 'count',
          action: 'Stocktake: Metformin 500mg 305 → 300 (-5)',
          detail: 'Shortage ETB 12'),
      AuditEntry(
          ts: mins(72 * 60),
          user: 'Meron (Admin)',
          type: 'stock',
          action: 'Registered Azithromycin 500mg',
          detail: 'Batch Z9 · 8 units'),
    ];
  }
}

class _Bucket {
  _Bucket(this.mk, this.sup);
  final int mk;
  final String sup;
  final Map<String, int> units = {};
}
