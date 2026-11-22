import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Export-ready view of a report. Keeping this value type independent of
/// widgets lets both PDF and Excel exports use exactly the rows on screen.
class ReportTable {
  const ReportTable({
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.rows,
    this.metrics = const [],
    this.total,
  });

  final String title;
  final String subtitle;
  final List<String> columns;
  final List<List<String>> rows;
  final List<(String, String, String)> metrics;
  final List<String>? total;
}

class ReportExport {
  ReportExport._();

  static Future<Uint8List> pdf(ReportTable table) async {
    final document = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansEthiopic-Regular.ttf'),
      ),
      bold: pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansEthiopic-Bold.ttf'),
      ),
    );
    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: table.columns.length > 6
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            table.title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          if (table.subtitle.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(table.subtitle, style: const pw.TextStyle(fontSize: 9)),
          ],
          if (table.metrics.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            for (final metric in table.metrics)
              pw.Text(
                '${metric.$1}: ${metric.$2}',
                style: const pw.TextStyle(fontSize: 9),
              ),
          ],
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: table.columns,
            data: [...table.rows, if (table.total != null) table.total!],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    return document.save();
  }

  static Uint8List excel(ReportTable table) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Report'];
    sheet.appendRow([TextCellValue(table.title)]);
    if (table.subtitle.isNotEmpty) {
      sheet.appendRow([TextCellValue(table.subtitle)]);
    }
    for (final metric in table.metrics) {
      sheet.appendRow([TextCellValue(metric.$1), TextCellValue(metric.$2)]);
    }
    sheet.appendRow(const []);
    sheet.appendRow(table.columns.map(TextCellValue.new).toList());
    for (final row in table.rows) {
      sheet.appendRow(row.map(TextCellValue.new).toList());
    }
    if (table.total != null) {
      sheet.appendRow(table.total!.map(TextCellValue.new).toList());
    }
    return Uint8List.fromList(workbook.encode()!);
  }

  static Future<void> sharePdf(ReportTable table, String filename) async {
    await _share(await pdf(table), '$filename.pdf', 'application/pdf');
  }

  static Future<bool> printPdf(ReportTable table, String filename) =>
      Printing.layoutPdf(name: '$filename.pdf', onLayout: (_) => pdf(table));

  static Future<void> shareExcel(ReportTable table, String filename) async {
    await _share(
      excel(table),
      '$filename.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  static Future<void> _share(
    Uint8List bytes,
    String filename,
    String mimeType,
  ) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: filename, mimeType: mimeType)],
        fileNameOverrides: [filename],
      ),
    );
  }
}
