import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {
  static Future<Uint8List> buildServiceReport(
      Map<String, dynamic> record,
      ) async {
    final pdf = pw.Document();

    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansSC-VariableFont_wght.ttf'),
    );

    final customer = record['customers'] ?? {};
    final vehicle = record['vehicles'] ?? {};
    final items = record['service_record_items'] as List? ?? [];

    final recordId = record['record_id']?.toString() ?? '';
    final reportNo = recordId.length >= 8
        ? 'SR-${recordId.substring(0, 8).toUpperCase()}'
        : 'SR-${DateTime.now().millisecondsSinceEpoch}';

    final date = _formatDate(record['created_at']?.toString());

    final customerName = _safeText(customer['name'], 'Not Provided');
    final customerPhone = _safeText(customer['phone'], 'Not Provided');
    final customerEmail = _safeText(customer['email'], 'Not Provided');

    final plateNumber = _safeText(vehicle['plate_number'], 'Not Provided');
    final carModel = _safeText(vehicle['car_model'], 'Not Provided');

    final problem = _safeText(
      record['problem_description'],
      'No problem description provided.',
    );

    final action = _safeText(
      record['service_action'],
      'No service action provided.',
    );

    final total = double.tryParse(record['total_price'].toString()) ??
        _calculateTotal(items);

    pw.MemoryImage? logoImage;

    try {
      final logoBytes = await rootBundle.load('assets/images/logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
        ),
        build: (context) {
          return [
            _buildHeader(logoImage, font),
            pw.SizedBox(height: 12),
            _buildReportMeta(reportNo, date, font),
            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _buildInfoBox(
                    title: 'CUSTOMER INFORMATION',
                    font: font,
                    rows: [
                      ['Name', customerName],
                      ['Phone', customerPhone],
                      ['Email', customerEmail],
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: _buildInfoBox(
                    title: 'VEHICLE INFORMATION',
                    font: font,
                    rows: [
                      ['Plate Number', plateNumber],
                      ['Car Model', carModel],
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            _buildTextSection(
              title: 'PROBLEM DESCRIPTION',
              text: problem,
              font: font,
            ),
            pw.SizedBox(height: 10),
            _buildTextSection(
              title: 'SERVICE ACTION',
              text: action,
              font: font,
            ),
            pw.SizedBox(height: 14),
            _buildItemsTable(items, font),
            pw.SizedBox(height: 10),
            _buildTotalBox(total, font),
            pw.SizedBox(height: 18),
            _buildFooter(font),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> viewServiceReport(Map<String, dynamic> record) async {
    final bytes = await buildServiceReport(record);
    final dir = await getTemporaryDirectory();

    final recordId = record['record_id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    final file = File(
      '${dir.path}/service_report_${recordId.replaceAll('-', '_')}.pdf',
    );

    await file.writeAsBytes(bytes);

    await OpenFilex.open(file.path);
  }

  static Future<void> shareServiceReport(Map<String, dynamic> record) async {
    final bytes = await buildServiceReport(record);

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'service_report.pdf',
    );
  }

  static pw.Widget _buildHeader(pw.MemoryImage? logoImage, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue800, width: 1.2),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        children: [
          if (logoImage != null)
            pw.SizedBox(
              width: 58,
              height: 58,
              child: pw.Image(logoImage),
            ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CAR SERVICE BOOKING &',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.Text(
                  'WORKSHOP MANAGEMENT SYSTEM',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Reliable Service  •  Quality Work  •  Customer Satisfaction',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildReportMeta(
      String reportNo,
      String date,
      pw.Font font,
      ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue900,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(child: _metaText('SERVICE REPORT NO.', reportNo, font)),
          pw.Expanded(child: _metaText('DATE', date, font)),
          pw.Expanded(child: _metaText('STATUS', 'COMPLETED', font)),
        ],
      ),
    );
  }

  static pw.Widget _metaText(String title, String value, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: font,
            color: PdfColors.white,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: font,
            color: PdfColors.white,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildInfoBox({
    required String title,
    required List<List<String>> rows,
    required pw.Font font,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: PdfColors.blue50,
            child: pw.Text(
              title,
              style: pw.TextStyle(
                font: font,
                color: PdfColors.blue900,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              children: rows.map((row) {
                return _infoRow(row[0], row[1], font);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(String label, String value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 65,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                font: font,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(':  ', style: pw.TextStyle(font: font, fontSize: 9)),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: font, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTextSection({
    required String title,
    required String text,
    required pw.Font font,
  }) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            color: PdfColors.blue50,
            child: pw.Text(
              title,
              style: pw.TextStyle(
                font: font,
                color: PdfColors.blue900,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text(
              text,
              style: pw.TextStyle(font: font, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable(List items, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'CHANGED PARTS / LABOUR',
          style: pw.TextStyle(
            font: font,
            color: PdfColors.blue900,
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.7),
            1: const pw.FlexColumnWidth(3.3),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.7),
            4: const pw.FlexColumnWidth(1.7),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue900),
              children: [
                _tableHeader('NO.', font),
                _tableHeader('ITEM / PART NAME', font),
                _tableHeader('QTY', font),
                _tableHeader('UNIT PRICE (RM)', font),
                _tableHeader('TOTAL (RM)', font),
              ],
            ),
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final qty = int.tryParse(item['quantity'].toString()) ?? 1;
              final price = double.tryParse(item['price'].toString()) ?? 0;
              final subtotal = qty * price;

              return pw.TableRow(
                children: [
                  _tableCell('${index + 1}', font, center: true),
                  _tableCell(_safeText(item['item_name'], '-'), font),
                  _tableCell('$qty', font, center: true),
                  _tableCell(price.toStringAsFixed(2), font, right: true),
                  _tableCell(subtotal.toStringAsFixed(2), font, right: true),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _tableHeader(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(7),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: font,
          color: PdfColors.white,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(
      String text,
      pw.Font font, {
        bool center = false,
        bool right = false,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(7),
      child: pw.Text(
        text,
        textAlign: right
            ? pw.TextAlign.right
            : center
            ? pw.TextAlign.center
            : pw.TextAlign.left,
        style: pw.TextStyle(font: font, fontSize: 8),
      ),
    );
  }

  static pw.Widget _buildTotalBox(double total, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        children: [
          pw.Spacer(),
          pw.Text(
            'TOTAL AMOUNT (RM)',
            style: pw.TextStyle(
              font: font,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
              fontSize: 12,
            ),
          ),
          pw.SizedBox(width: 18),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue900,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              total.toStringAsFixed(2),
              style: pw.TextStyle(
                font: font,
                color: PdfColors.white,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Font font) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Center(
        child: pw.Text(
          'Thank you for choosing our service. We appreciate your trust and support.',
          style: pw.TextStyle(
            font: font,
            fontSize: 9,
            color: PdfColors.blue900,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static String _safeText(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _formatDate(String? dateText) {
    if (dateText == null || dateText.isEmpty) return 'Not Provided';

    final date = DateTime.tryParse(dateText);
    if (date == null) return 'Not Provided';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  static double _calculateTotal(List items) {
    double total = 0;

    for (final item in items) {
      final qty = int.tryParse(item['quantity'].toString()) ?? 1;
      final price = double.tryParse(item['price'].toString()) ?? 0;
      total += qty * price;
    }

    return total;
  }
}