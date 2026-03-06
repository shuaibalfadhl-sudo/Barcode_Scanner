import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/user_helper.dart';

class BarcodeGeneratorScreen extends StatefulWidget {
  final Map<String, dynamic> product; // This now receives the 'bundle' data
  final String? scannedBarcode;
  final int? scannedBarcodeTypeId;
  final String? sourceAction;

  const BarcodeGeneratorScreen({super.key, required this.product, this.scannedBarcode, this.scannedBarcodeTypeId, this.sourceAction});

  @override
  State<BarcodeGeneratorScreen> createState() => _BarcodeGeneratorScreenState();
}

class _BarcodeGeneratorScreenState extends State<BarcodeGeneratorScreen> {
  final TextEditingController _valueController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _lengthController = TextEditingController();
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();

  Map<String, String> _barcodeTypes = {'0': 'N/A'};
  Map<String, String> _weightUnits = {'0': 'N/A'};

  String _selectedBarcodeType = '0';
  String _selectedWeightUnit = '0';
  String _selectedDimUnit = '0';
  bool _isCbmChecked = false;
  bool _isSaving = false;
  bool _isInitialLoading = true;

  final Map<String, String> _dimUnits = {'0': 'N/A', '1': 'MM', '2': 'CM', '3': 'M', '4': 'IN', '5': 'FT'};

  String _cleanString(dynamic val) {
    if (val == null || val.toString() == "null" || val.toString().trim().isEmpty) {
      return "";
    }
    return val.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    _valueController.text = _cleanString(widget.scannedBarcode ?? widget.product['barcode_value']);
    _weightController.text = _cleanString(widget.product['weight']);

    if (widget.scannedBarcodeTypeId != null) {
      _selectedBarcodeType = widget.scannedBarcodeTypeId.toString();
    } else if (widget.scannedBarcode != null) {
      final barcodeValue = widget.scannedBarcode!.trim();
      if ((barcodeValue.length == 12 || barcodeValue.length == 13) && RegExp(r'^[0-9]+$').hasMatch(barcodeValue)) {
        _selectedBarcodeType = '1';
      } else {
        _selectedBarcodeType = '2';
      }
    } else if (widget.product['barcode_type_id'] != null) {
      _selectedBarcodeType = widget.product['barcode_type_id'].toString();
    }

    if (widget.product['weight_unit_id'] != null) {
      _selectedWeightUnit = widget.product['weight_unit_id'].toString();
    }

    if (widget.product['cbm_unit_id'] != null && widget.product['cbm_unit_id'].toString() != "null") {
      _isCbmChecked = true;
      _selectedDimUnit = widget.product['cbm_unit_id'].toString();
      _lengthController.text = _cleanString(widget.product['cbm_length']);
      _widthController.text = _cleanString(widget.product['cbm_width']);
      _heightController.text = _cleanString(widget.product['cbm_height']);
    }

    _valueController.addListener(() => setState(() {}));
    _weightController.addListener(() => setState(() {}));
    _lengthController.addListener(() => setState(() {}));
    _widthController.addListener(() => setState(() {}));
    _heightController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _valueController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  // --- NEW CHECKSUM CALCULATOR ---
  String _calculateEan13Checksum(String code) {
    if (code.length < 12) return "";

    int sum = 0;
    for (int i = 0; i < 12; i++) {
      int digit = int.parse(code[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }

    int checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit.toString();
  }

  // --- UPDATED AUTO GENERATOR ---
  void _generateUniqueBarcode() {
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    String newValue = "";

    if (_selectedBarcodeType == '1') {
      String baseCode = timestamp.substring(timestamp.length - 12);
      String checkDigit = _calculateEan13Checksum(baseCode);
      newValue = baseCode + checkDigit;
    } else if (_selectedBarcodeType == '2') {
      newValue = "VTX${timestamp.substring(timestamp.length - 7)}";
    } else {
      newValue = timestamp;
    }

    setState(() {
      _valueController.text = newValue;
    });
  }

  Future<void> _loadInitialData() async {
    try {
      await Future.wait([_fetchBarcodeTypes(), _fetchWeightUnits()]);
    } catch (e) {
      debugPrint("🔴 Error: $e");
    } finally {
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  Future<void> _fetchBarcodeTypes() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await http.get(Uri.parse('http://192.168.0.143:8056/items/barcode_type')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body)['data'];
        await prefs.setString('cached_barcode_types', json.encode(data));

        final Map<String, String> fetchedTypes = {'0': 'N/A'};
        for (var item in data) {
          if (item['status'] == "published" || item['is_active'] == 1 || item['status'] == "Active") {
            fetchedTypes[item['id'].toString()] = item['name'].toString();
          } else {
            fetchedTypes[item['id'].toString()] = item['name'].toString();
          }
        }
        if (mounted) setState(() => _barcodeTypes = fetchedTypes);
      }
    } catch (_) {
      final cached = prefs.getString('cached_barcode_types');
      if (cached != null) {
        final List data = json.decode(cached);
        final Map<String, String> fetchedTypes = {'0': 'N/A'};
        for (var item in data) {
          fetchedTypes[item['id'].toString()] = item['name'].toString();
        }
        if (mounted) setState(() => _barcodeTypes = fetchedTypes);
      }
    }
  }

  Future<void> _fetchWeightUnits() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await http.get(Uri.parse('http://192.168.0.143:8056/items/weight_unit')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body)['data'];
        await prefs.setString('cached_weight_units', json.encode(data));

        final Map<String, String> fetchedUnits = {'0': 'N/A'};
        for (var item in data) {
          if (item['is_active'] == 1) fetchedUnits[item['id'].toString()] = item['code'].toString();
        }
        if (mounted) setState(() => _weightUnits = fetchedUnits);
      }
    } catch (_) {
      final cached = prefs.getString('cached_weight_units');
      if (cached != null) {
        final List data = json.decode(cached);
        final Map<String, String> fetchedUnits = {'0': 'N/A'};
        for (var item in data) {
          if (item['is_active'] == 1) fetchedUnits[item['id'].toString()] = item['code'].toString();
        }
        if (mounted) setState(() => _weightUnits = fetchedUnits);
      }
    }
  }

  // --- UPDATED VALIDATION ---
  String? get _barcodeError {
    final val = _valueController.text.trim();
    if (val.isEmpty) return "Barcode is required";

    if (_selectedBarcodeType == '1') {
      if (!RegExp(r'^[0-9]+$').hasMatch(val)) {
        return "EAN-13 must be numbers only";
      }
      if (val.length < 12 || val.length > 13) {
        return "EAN-13 must be 12 or 13 digits";
      }

      // Checksum Validation
      if (val.length == 13) {
        final expectedCheckDigit = _calculateEan13Checksum(val);
        final actualCheckDigit = val[12];
        if (actualCheckDigit != expectedCheckDigit) {
          return "Invalid checksum (Expected: $expectedCheckDigit)";
        }
      }
    }

    if (_selectedBarcodeType == '2') {
      if (val.length < 3) {
        return "Code 128 is too short";
      }

      if (val.length == 13 && RegExp(r'^[0-9]+$').hasMatch(val)) {
        final expectedCheckDigit = _calculateEan13Checksum(val);
        final actualCheckDigit = val[12];
        if (actualCheckDigit == expectedCheckDigit) {
          return "Valid EAN-13 detected. Please switch type to EAN-13.";
        }
      }
    }

    return null;
  }

  String? get _weightError {
    if (_weightController.text.isEmpty) return "Required";
    final val = double.tryParse(_weightController.text);
    if (val == null) return "Invalid";
    if (val <= 0) return "Must be > 0";
    return null;
  }

  String? get _unitError {
    if (_selectedWeightUnit == '0') return "Req";
    return null;
  }

  String? _getDimError(TextEditingController controller) {
    if (!_isCbmChecked) return null;
    if (controller.text.isEmpty) return "Req";
    final val = double.tryParse(controller.text);
    if (val == null || val <= 0) return "Inv";
    return null;
  }

  bool get _isFormValid {
    if (_selectedBarcodeType == '0' || _barcodeError != null) return false;
    if (_weightController.text.isEmpty || _weightError != null || _selectedWeightUnit == '0') return false;

    if (_isCbmChecked) {
      if (_selectedDimUnit == '0') return false;
      if (_lengthController.text.isEmpty || _getDimError(_lengthController) != null) return false;
      if (_widthController.text.isEmpty || _getDimError(_widthController) != null) return false;
      if (_heightController.text.isEmpty || _getDimError(_heightController) != null) return false;
    }

    return true;
  }

  Future<void> _saveProduct() async {
    setState(() => _isSaving = true);

    final id = widget.product['id'];

    // --- GET LOGGED-IN USER ID ---
    final userId = await UserHelper.getLoggedInUserId();

    // --- CHECK IF BUNDLE ALREADY HAS A BARCODE ---
    final currentBarcode = (widget.product['barcode_value'] ?? "").toString().trim();
    final hasExistingBarcode = currentBarcode.isNotEmpty;

    debugPrint('DEBUG: Bundle ID=$id, userId=$userId, hasExistingBarcode=$hasExistingBarcode, currentBarcode=$currentBarcode');

    final Map<String, dynamic> body = {
      'barcode_value': _valueController.text.trim(),
      'barcode_type_id': int.parse(_selectedBarcodeType),
      'weight': double.tryParse(_weightController.text) ?? 0.0,
      'weight_unit_id': int.parse(_selectedWeightUnit),
      if (_isCbmChecked) ...{
        'cbm_length': double.tryParse(_lengthController.text) ?? 0.0,
        'cbm_width': double.tryParse(_widthController.text) ?? 0.0,
        'cbm_height': double.tryParse(_heightController.text) ?? 0.0,
        'cbm_unit_id': int.parse(_selectedDimUnit),
      },
      // --- USER TRACKING - ONLY UPDATED_BY ---
      if (userId != null) ...{'updated_by': userId, 'updated_at': DateTime.now().toIso8601String()},
    };

    debugPrint('DEBUG: Request body keys: ${body.keys.toList()}');
    debugPrint('DEBUG: updated_by=${body['updated_by']}');

    final bool isScanned = widget.sourceAction == 'scan' || widget.sourceAction == 'rescan' || widget.scannedBarcode != null;
    final bool isRescan = widget.sourceAction == 'rescan';
    final bool isGenerate = widget.sourceAction == 'generate';
    final bool isRegenerate = widget.sourceAction == 'regenerate';

    try {
      final response = await http
          .patch(Uri.parse('http://192.168.0.143:8056/items/product_bundles/$id'), headers: {'Content-Type': 'application/json'}, body: json.encode(body))
          .timeout(const Duration(seconds: 5));

      debugPrint('DEBUG: API Response status=${response.statusCode}');
      debugPrint('DEBUG: API Response body=${response.body}');

      if (response.statusCode == 200 && mounted) {
        Navigator.pop(context, {
          'saved': true,
          'barcode': _valueController.text.trim(),
          'updated_data': body,
          'is_scanned': isScanned,
          'is_rescan': isRescan,
          'is_generated': isGenerate,
          'is_regenerated': isRegenerate,
          'action': widget.sourceAction,
          'is_offline': false,
        });
      }
    } catch (e) {
      debugPrint("🔴 Save Error (Offline Mode Triggered): $e");
      if (mounted) {
        Navigator.pop(context, {
          'saved': true,
          'barcode': _valueController.text.trim(),
          'updated_data': body,
          'is_scanned': isScanned,
          'is_rescan': isRescan,
          'is_generated': isGenerate,
          'is_regenerated': isRegenerate,
          'action': widget.sourceAction,
          'is_offline': true,
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 80,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.product['bundle_name'] ?? 'Bundle Generator', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [_appBarBadge("SKU: ${widget.product['bundle_sku'] ?? 'N/A'}"), const SizedBox(width: 8), _appBarBadge("ID: ${_getProductId(widget.product)}")]),
          ],
        ),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSectionCard(
              title: "Barcode Configuration",
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _barcodeTypes.containsKey(_selectedBarcodeType) ? _selectedBarcodeType : '0',
                    decoration: _inputDecoration("Barcode Type", Icons.category),
                    items: _barcodeTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (val) => setState(() => _selectedBarcodeType = val!),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _valueController,
                          decoration: _inputDecoration("Barcode Value", Icons.edit_note, error: _barcodeError),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _selectedBarcodeType == '0' ? null : _generateUniqueBarcode,
                          child: const Icon(Icons.auto_fix_high),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: "Bundle Specifications",
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _weightController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration("Weight", Icons.scale, error: _weightError),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _weightUnits.containsKey(_selectedWeightUnit) ? _selectedWeightUnit : '0',
                          decoration: _inputDecoration("Unit", null, error: _unitError),
                          items: _weightUnits.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                          onChanged: (val) => setState(() => _selectedWeightUnit = val!),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Include CBM Dimensions", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    value: _isCbmChecked,
                    activeColor: Colors.green.shade800,
                    onChanged: (val) => setState(() => _isCbmChecked = val!),
                  ),
                  if (_isCbmChecked) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDimField(_lengthController, "L", error: _getDimError(_lengthController)),
                        _buildDimField(_widthController, "W", error: _getDimError(_widthController)),
                        _buildDimField(_heightController, "H", error: _getDimError(_heightController)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: DropdownButtonFormField<String>(
                            value: _selectedDimUnit,
                            decoration: InputDecoration(isDense: true, labelText: "Unit", errorText: _selectedDimUnit == '0' ? "Req" : null),
                            items: _dimUnits.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                            onChanged: (val) => setState(() => _selectedDimUnit = val!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildPreviewSection(),
            const SizedBox(height: 32),
            if (_isSaving)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), foregroundColor: Colors.green.shade800),
                      onPressed: _printBarcode,
                      icon: const Icon(Icons.print),
                      label: const Text("PRINT"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), elevation: 2),
                      onPressed: _isFormValid ? _saveProduct : null,
                      icon: const Icon(Icons.save),
                      label: const Text("SAVE BUNDLE"),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData? icon, {String? hint, String? error}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      isDense: true,
    );
  }

  Widget _buildDimField(TextEditingController controller, String hint, {String? error}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: hint,
            errorText: error,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    return Column(
      children: [
        const Text(
          "LIVE BARCODE PREVIEW",
          style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            children: [
              if (_valueController.text.isNotEmpty && _selectedBarcodeType != '0' && _barcodeError == null)
                BarcodeWidget(
                  barcode: _selectedBarcodeType == '1' ? Barcode.ean13() : Barcode.code128(),
                  data: _valueController.text,
                  width: double.infinity,
                  height: 100,
                  drawText: true,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                )
              else
                Text(
                  _barcodeError ?? "Waiting for valid data...",
                  style: TextStyle(color: _barcodeError != null ? Colors.red : Colors.grey, fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _appBarBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.white)),
    );
  }

  dynamic _getProductId(Map<String, dynamic> p) {
    for (var k in ['product_id', 'id', 'itemId', 'item_id']) {
      if (p[k] != null) return p[k];
    }
    return "N/A";
  }

  Future<void> _printBarcode() async {
    if (_valueController.text.isEmpty || _selectedBarcodeType == '0' || _barcodeError != null) return;

    final bool? withDetails = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
            ),
            const SizedBox(height: 20),
            Text(
              "Print Options",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green.shade800),
            ),
            const SizedBox(height: 8),
            const Text("Choose your layout style for the label:", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            _buildPrintOption(context, icon: Icons.qr_code, title: "Barcode Only", subtitle: "Minimalist: Name & Barcode number", onTap: () => Navigator.pop(context, false)),
            const SizedBox(height: 12),
            _buildPrintOption(context, icon: Icons.receipt_long, title: "With Details", subtitle: "Full Specs: SKU, Weight, and CBM", onTap: () => Navigator.pop(context, true), isPrimary: true),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    if (withDetails == null) return;

    try {
      final pw.Document pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  widget.product['bundle_name']?.toString().toUpperCase() ?? 'BUNDLE',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 5),
                pw.BarcodeWidget(
                  barcode: _selectedBarcodeType == '1' ? pw.Barcode.ean13() : pw.Barcode.code128(),
                  data: _valueController.text.trim(),
                  width: 180,
                  height: 70,
                  drawText: true,
                  textStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                if (withDetails) ...[
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 0.5),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("SKU:", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text(widget.product['bundle_sku'] ?? 'N/A', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Weight:", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text("${_weightController.text} ${_weightUnits[_selectedWeightUnit]}", style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  if (_isCbmChecked) ...[
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Dims (LWH):", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.Text("${_lengthController.text}x${_widthController.text}x${_heightController.text} ${_dimUnits[_selectedDimUnit]}", style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                  pw.SizedBox(height: 5),
                  pw.Divider(thickness: 0.5),
                ],
              ],
            );
          },
        ),
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      debugPrint('🔴 Print Error: $e');
    }
  }

  Widget _buildPrintOption(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap, bool isPrimary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.green.shade50 : Colors.grey.shade50,
          border: Border.all(color: isPrimary ? Colors.green.shade200 : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, color: isPrimary ? Colors.green.shade800 : Colors.grey.shade700, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
