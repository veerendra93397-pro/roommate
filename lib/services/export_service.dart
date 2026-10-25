import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models.dart';

/// Builds a monthly report (PDF or Excel) from the data already loaded in AppState
/// and opens the phone's share sheet (WhatsApp, Drive, email, save...).
class ExportService {
  static List<Expense> _expenses(DateTime month) => appState.expenses
      .where((e) => e.date.year == month.year && e.date.month == month.month)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  static List<Settlement> _payments(DateTime month) => appState.settlements
      .where((s) => s.date.year == month.year && s.date.month == month.month)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // The PDF's built-in font has no rupee sign, so the PDF uses "Rs."
  static String _rs(double v) => 'Rs. ${v.toStringAsFixed(2)}';

  static String _slug(DateTime m) =>
      'RoomMate_${m.year}-${m.month.toString().padLeft(2, '0')}';

  /// Per member: paid, share and net for the month.
  static List<List<Object>> _people(DateTime month) {
    final ex = _expenses(month);
    return [
      for (final m in appState.members)
        () {
          final paid = ex.where((e) => e.paidBy == m.name).fold(0.0, (s, e) => s + e.amount);
          final share = ex.fold(0.0, (s, e) => s + (e.shares[m.name] ?? 0));
          return <Object>[m.name, paid, share, paid - share];
        }(),
    ];
  }

  // ───────────── PDF ─────────────

  static Future<void> sharePdf(DateTime month) async {
    final ex = _expenses(month);
    final pays = _payments(month);
    final total = ex.fold(0.0, (s, e) => s + e.amount);
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Text('RoomMate - Monthly Report',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('${appState.roomName}  |  ${monthYear(month)}'),
          pw.SizedBox(height: 14),
          pw.Text('Total spent: ${_rs(total)}   |   Expenses: ${ex.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Text('Who paid / who owes (this month)',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Member', 'Paid', 'Share', 'Net'],
            data: [
              for (final r in _people(month))
                [r[0], _rs(r[1] as double), _rs(r[2] as double), _rs(r[3] as double)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 16),
          pw.Text('Expenses',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (ex.isEmpty)
            pw.Text('No expenses this month.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Title', 'Category', 'Paid by', 'Amount'],
              data: [
                for (final e in ex)
                  [fmtDate(e.date), e.title, e.category.label, e.paidBy, _rs(e.amount)],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          pw.SizedBox(height: 16),
          pw.Text('Payments between roommates',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (pays.isEmpty)
            pw.Text('No payments this month.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'From', 'To', 'Amount'],
              data: [
                for (final s in pays) [fmtDate(s.date), s.from, s.to, _rs(s.amount)],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          pw.SizedBox(height: 16),
          pw.Text('Current balances (all time)',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Member', 'Balance'],
            data: [
              for (final m in appState.members)
                [
                  m.name,
                  () {
                    final b = appState.balanceOf(m.name);
                    if (b.abs() < 0.005) return 'Settled';
                    return b > 0 ? 'To receive ${_rs(b)}' : 'To pay ${_rs(-b)}';
                  }(),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    await _share(await doc.save(), '${_slug(month)}.pdf', 'application/pdf');
  }

  // ───────────── Excel ─────────────

  static Future<void> shareExcel(DateTime month) async {
    final ex = _expenses(month);
    final pays = _payments(month);
    final book = xl.Excel.createExcel();

    final summary = book['Summary'];
    summary.appendRow([xl.TextCellValue('Room'), xl.TextCellValue(appState.roomName)]);
    summary.appendRow([xl.TextCellValue('Month'), xl.TextCellValue(monthYear(month))]);
    summary.appendRow([
      xl.TextCellValue('Total spent'),
      xl.DoubleCellValue(ex.fold(0.0, (s, e) => s + e.amount)),
    ]);
    summary.appendRow([xl.TextCellValue('Expenses'), xl.IntCellValue(ex.length)]);
    summary.appendRow([xl.TextCellValue('')]);
    summary.appendRow([
      xl.TextCellValue('Member'),
      xl.TextCellValue('Paid'),
      xl.TextCellValue('Share'),
      xl.TextCellValue('Net (this month)'),
      xl.TextCellValue('Balance (all time)'),
    ]);
    for (final r in _people(month)) {
      summary.appendRow([
        xl.TextCellValue(r[0] as String),
        xl.DoubleCellValue(r[1] as double),
        xl.DoubleCellValue(r[2] as double),
        xl.DoubleCellValue(r[3] as double),
        xl.DoubleCellValue(appState.balanceOf(r[0] as String)),
      ]);
    }

    final sheet = book['Expenses'];
    final names = appState.names;
    sheet.appendRow([
      xl.TextCellValue('Date'),
      xl.TextCellValue('Title'),
      xl.TextCellValue('Category'),
      xl.TextCellValue('Paid by'),
      xl.TextCellValue('Amount'),
      for (final n in names) xl.TextCellValue('Share: $n'),
    ]);
    for (final e in ex) {
      sheet.appendRow([
        xl.TextCellValue('${fmtDate(e.date)}, ${e.date.year}'),
        xl.TextCellValue(e.title),
        xl.TextCellValue(e.category.label),
        xl.TextCellValue(e.paidBy),
        xl.DoubleCellValue(e.amount),
        for (final n in names) xl.DoubleCellValue(e.shares[n] ?? 0),
      ]);
    }

    final pay = book['Payments'];
    pay.appendRow([
      xl.TextCellValue('Date'),
      xl.TextCellValue('From'),
      xl.TextCellValue('To'),
      xl.TextCellValue('Amount'),
    ]);
    for (final s in pays) {
      pay.appendRow([
        xl.TextCellValue('${fmtDate(s.date)}, ${s.date.year}'),
        xl.TextCellValue(s.from),
        xl.TextCellValue(s.to),
        xl.DoubleCellValue(s.amount),
      ]);
    }

    book.delete('Sheet1');
    final bytes = book.encode();
    if (bytes == null) throw AppException('Could not create the Excel file.');
    await _share(
      bytes,
      '${_slug(month)}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  static Future<void> _share(List<int> bytes, String name, String mime) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mime)],
      subject: 'RoomMate report',
    );
  }
}
