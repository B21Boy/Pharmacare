import 'package:material_ui/material_ui.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/widgets/status_chip.dart';
import '../domain/medicine.dart';
import '../domain/stock_overview.dart';

/// One row of the inventory list. Stateless and cheap to rebuild.
class MedicineTile extends StatelessWidget {
  const MedicineTile({super.key, required this.stock, required this.tr, required this.onTap});

  final MedStock stock;
  final Tr tr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = stock.medicine;
    final f = stock.flags;
    final sub = [
      if (m.strength.isNotEmpty) m.strength,
      tr.t(m.form.labelKey),
      tr.category(m.categoryId),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 2, children: [
                    if (m.type != MedType.otc)
                      StatusChip(tr.t(m.type.labelKey),
                          tone: m.type == MedType.controlled ? ChipTone.purple : ChipTone.blue),
                    if (f.expired) StatusChip(tr.t('Expired'), tone: ChipTone.red),
                    if (f.soon) StatusChip(tr.t('Expiring soon'), tone: ChipTone.amber),
                    if (f.out)
                      StatusChip(tr.t('Out of stock'), tone: ChipTone.red)
                    else if (f.low)
                      StatusChip(tr.t('Low stock'), tone: ChipTone.amber),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${stock.sellable}', style: Theme.of(context).textTheme.titleLarge),
                Text(tr.t('units'), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
