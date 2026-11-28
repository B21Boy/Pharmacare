import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../chat/presentation/chat_controller.dart';
import '../../sales/presentation/sale_form_controller.dart';
import 'stock_providers.dart';

class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({
    super.key,
    this.forSale = false,
    this.forChat = false,
    this.forRegister = false,
  });
  final bool forSale;
  final bool forChat;
  final bool forRegister;

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes
        .map((b) => b.rawValue?.trim())
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (code.isEmpty) return;
    _handled = true;
    if (widget.forRegister) {
      context.pop(code);
      return;
    }
    final medicines = ref.read(medicinesProvider).valueOrNull ?? const [];
    final matches = medicines.where((m) => m.barcode.trim() == code);
    final match = matches.isEmpty ? null : matches.first;
    if (match != null) {
      if (widget.forChat) {
        ref.read(chatProvider.notifier).pick(match.id);
        context.go('/chat');
      } else if (widget.forSale) {
        final available =
            ref.read(stockOverviewProvider)[match.id]?.sellable ?? 0;
        if (available > 0) {
          ref.read(saleFormProvider.notifier).add(match.id);
        }
        context.go('/sales');
        if (available == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${match.name} has no sellable stock.')),
          );
        }
      } else {
        context.go('/inventory/medicine/${match.id}');
      }
    } else {
      if (!widget.forSale && !widget.forChat) {
        ref.read(inventoryQueryProvider.notifier).setText(code);
        ref.read(inventoryQueryProvider.notifier).setFilter(StockFilter.all);
        context.go('/inventory');
      } else if (widget.forSale) {
        context.go('/sales');
      } else {
        context.go('/chat');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No medicine found for barcode $code.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan barcode')),
    body: Stack(
      children: [
        Positioned.fill(child: MobileScanner(onDetect: _onDetect)),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Point the camera at a medicine barcode',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
