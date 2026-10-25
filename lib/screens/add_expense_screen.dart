import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/bill_scanner.dart';
import '../theme.dart';
import '../widgets.dart';
import 'expense_details_screen.dart';

class AddExpenseScreen extends StatefulWidget {
  /// When set, the screen edits this expense instead of creating a new one.
  final Expense? editing;
  const AddExpenseScreen({super.key, this.editing});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _amount = TextEditingController();
  final _desc = TextEditingController();
  Category _category = Category.rent;
  String _paidBy = appState.names.contains(appState.userName)
      ? appState.userName
      : (appState.names.isEmpty ? '' : appState.names.first);
  int _split = 0; // 0 = equal, 1 = custom

  // Bill photo
  final _picker = ImagePicker();
  Uint8List? _bill;
  bool _billChanged = false;
  bool _billLoading = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _amount.text = (e.amount - e.amount.truncate()).abs() < 0.005
          ? e.amount.toStringAsFixed(0)
          : e.amount.toStringAsFixed(2);
      _desc.text = e.title == e.category.label ? '' : e.title;
      _category = e.category;
      if (appState.names.contains(e.paidBy)) _paidBy = e.paidBy;
      _split = e.isCustomSplit ? 1 : 0;
      if (e.hasBill) {
        _billLoading = true;
        appState.loadBill(e.id).then((b) {
          if (mounted) {
            setState(() {
              _bill = b;
              _billLoading = false;
            });
          }
        }).catchError((_) {
          if (mounted) setState(() => _billLoading = false);
        });
      }
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickBill() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo of the bill'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            if (_bill != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
                title: const Text('Remove photo', style: TextStyle(color: AppColors.red)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'remove') {
      setState(() {
        _bill = null;
        _billChanged = true;
      });
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 60,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 450 * 1024) {
        _toast('That photo is too large. Try a smaller one.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _bill = bytes;
        _billChanged = true;
      });
    } catch (e) {
      if (mounted) _toast('Could not open the photo: $e');
    }
  }

  /// Take / choose a photo of a bill, read it on the phone and fill in the form.
  Future<void> _scanBill() async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo of the bill'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    setState(() => _scanning = true);
    try {
      final file = await _picker.pickImage(
        source: choice,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (file == null) return;
      final scan = await billScanner.scan(file.path);
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        if (scan.total != null) {
          final v = scan.total!;
          _amount.text = (v - v.truncate()).abs() < 0.005 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
        }
        if (scan.shop != null && _desc.text.trim().isEmpty) _desc.text = scan.shop!;
        if (scan.category != null) _category = scan.category!;
        if (bytes.length <= 450 * 1024) {
          _bill = bytes; // also keep the photo as the bill
          _billChanged = true;
        }
      });
      _toast(scan.total == null
          ? 'Could not find the total. Please type the amount.'
          : 'Read ${rupee(scan.total!)}${scan.shop != null ? ' from ${scan.shop}' : ''}. Please check it.');
    } catch (e) {
      if (mounted) _toast('Could not read the bill: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Who shares an equal split: everyone for a new expense, the original people when editing.
  List<String> _participants() {
    final e = widget.editing;
    if (e == null) return appState.names;
    final p = e.shares.entries
        .where((s) => s.value > 0 && appState.names.contains(s.key))
        .map((s) => s.key)
        .toList();
    return p.isEmpty ? appState.names : p;
  }

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.trim());
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    final title = _desc.text.trim().isEmpty ? _category.label : _desc.text.trim();
    final expense = Expense(
      id: widget.editing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      category: _category,
      amount: amt,
      paidBy: _paidBy,
      date: widget.editing?.date ?? DateTime.now(),
      shares: equalShares(amt, _participants()),
      isCustomSplit: _split == 1,
    );

    Expense? result = expense;
    if (_split == 1) {
      result = await Navigator.push<Expense>(
        context,
        MaterialPageRoute(
          builder: (_) => ExpenseDetailsScreen(expense: expense, draft: true),
        ),
      );
    }
    if (result == null || !mounted) return;

    final editing = widget.editing != null;
    guard(
      context,
      editing
          ? appState.editExpense(
              result,
              newBill: _billChanged ? _bill : null,
              removeBill: _billChanged && _bill == null,
            )
          : appState.addExpense(result, bill: _bill),
    );
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    messenger.showSnackBar(
      SnackBar(content: Text(editing ? 'Expense updated' : 'Expense added')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'Add Expense' : 'Edit Expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              for (final c in Category.values)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _category = c),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _category == c ? AppColors.of(context).tint : AppColors.of(context).card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _category == c ? AppColors.primary : AppColors.of(context).border,
                          width: _category == c ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(c.icon, color: c.color),
                          const SizedBox(height: 6),
                          Text(
                            c.shortLabel,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.editing == null && !kIsWeb) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _scanning ? null : _scanBill,
              icon: _scanning
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_scanning ? 'Reading bill...' : 'Scan bill to auto-fill'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Amount', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(prefixText: '₹ ', hintText: '0'),
          ),
          const SizedBox(height: 16),
          const Text('Description (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(hintText: 'e.g. Groceries, Bill etc.'),
          ),
          const SizedBox(height: 16),
          const Text('Paid By', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _paidBy,
            items: [
              for (final m in appState.members)
                DropdownMenuItem(
                  value: m.name,
                  child: Text(m.name == appState.userName ? '${m.name} (You)' : m.name),
                ),
            ],
            onChanged: (v) => setState(() => _paidBy = v ?? _paidBy),
          ),
          const SizedBox(height: 16),
          const Text('Split Type', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentToggle(
            options: const ['Equal', 'Custom'],
            selected: _split,
            onChanged: (i) => setState(() => _split = i),
          ),
          if (_split == 1)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'You will choose who shares and how much on the next screen.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          const Text('Bill photo (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (_billLoading)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_bill != null)
            Stack(
              children: [
                GestureDetector(
                  onTap: () => showBillViewer(context, _bill!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      _bill!,
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                      onPressed: () => setState(() {
                        _bill = null;
                        _billChanged = true;
                      }),
                    ),
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _pickBill,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add bill photo'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          const SizedBox(height: 26),
          PrimaryButton(
            label: _split == 1
                ? 'Next: Split Details'
                : (widget.editing == null ? 'Add Expense' : 'Save Changes'),
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
