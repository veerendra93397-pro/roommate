import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models.dart';

/// What was read from a bill photo. Everything can be null (not found).
class BillScan {
  final double? total;
  final String? shop;
  final Category? category;
  final String rawText;
  const BillScan({this.total, this.shop, this.category, this.rawText = ''});
}

/// Reads a bill photo on the phone (Google ML Kit, no internet needed)
/// and guesses the total amount, the shop name and the category.
class BillScanner {
  static const _totalWords = [
    'grand total', 'net payable', 'amount payable', 'net amount', 'total amount',
    'bill amount', 'amount due', 'total due', 'to pay', 'total', 'amount',
  ];
  static const _skipWords = ['sub total', 'subtotal', 'sub-total', 'tax', 'gst', 'cgst', 'sgst', 'discount', 'change', 'cash', 'tendered', 'qty', 'items'];

  static final _number = RegExp(r'\d[\d,]*(?:\.\d{1,2})?');

  Future<BillScan> scan(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return parse(result.text);
    } finally {
      await recognizer.close();
    }
  }

  List<double> _numbersIn(String line) {
    final out = <double>[];
    for (final m in _number.allMatches(line)) {
      final raw = m.group(0)!.replaceAll(',', '');
      if (raw.replaceAll('.', '').length >= 10) continue; // phone / card / id numbers
      final v = double.tryParse(raw);
      if (v != null && v > 0 && v < 1000000) out.add(v);
    }
    return out;
  }

  BillScan parse(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return BillScan(rawText: text);

    // 1) amount: numbers on (or just below) lines that say "total", "amount payable"...
    double? best;
    for (final word in _totalWords) {
      final found = <double>[];
      for (var i = 0; i < lines.length; i++) {
        final low = lines[i].toLowerCase();
        if (!low.contains(word)) continue;
        if (_skipWords.any(low.contains) && !low.contains('grand') && !low.contains('net')) {
          continue;
        }
        found.addAll(_numbersIn(lines[i]));
        if (i + 1 < lines.length) found.addAll(_numbersIn(lines[i + 1])); // value on the next line
      }
      if (found.isNotEmpty) {
        found.sort();
        best = found.last;
        break;
      }
    }
    // 2) otherwise the biggest amount with decimals, then the biggest number
    if (best == null) {
      final decimals = <double>[];
      final all = <double>[];
      for (final l in lines) {
        for (final m in _number.allMatches(l)) {
          final raw = m.group(0)!.replaceAll(',', '');
          final v = double.tryParse(raw);
          if (v == null || v <= 0 || v >= 1000000 || raw.replaceAll('.', '').length >= 10) continue;
          all.add(v);
          if (raw.contains('.')) decimals.add(v);
        }
      }
      final pool = decimals.isNotEmpty ? decimals : all;
      if (pool.isNotEmpty) {
        pool.sort();
        best = pool.last;
      }
    }

    // 3) shop name: first of the top lines that looks like a name
    String? shop;
    for (final l in lines.take(6)) {
      final low = l.toLowerCase();
      final letters = RegExp(r'[A-Za-z]').allMatches(l).length;
      if (letters < 3 || letters < l.length * 0.5) continue;
      if (['invoice', 'receipt', 'bill', 'tax', 'gst', 'cash memo', 'welcome', 'tel', 'phone', 'date']
          .any(low.contains)) {
        continue;
      }
      shop = l.length > 40 ? l.substring(0, 40) : l;
      break;
    }

    // 4) category guess
    final lowAll = text.toLowerCase();
    Category? cat;
    bool has(List<String> w) => w.any(lowAll.contains);
    if (has(['electricity', 'bescom', 'kwh', 'power supply'])) {
      cat = Category.electricity;
    } else if (has(['water bill', 'water supply', 'bwssb'])) {
      cat = Category.water;
    } else if (has(['rent receipt', 'house rent', 'rent for'])) {
      cat = Category.rent;
    } else if (has(['restaurant', 'hotel', 'cafe', 'bakery', 'mart', 'grocer', 'supermarket',
        'kirana', 'provision', 'vegetable', 'fruits', 'milk', 'dmart', 'reliance fresh'])) {
      cat = Category.food;
    }

    return BillScan(total: best, shop: shop, category: cat, rawText: text);
  }
}

final BillScanner billScanner = BillScanner();
