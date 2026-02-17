import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class BarcodeGeneratorScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final String? scannedBarcode;
  final int? scannedBarcodeTypeId;
  final String? sourceAction; // 'rescan' or 'regenerate'

  const BarcodeGeneratorScreen({
    super.key,
    required this.product,
    this.scannedBarcode,
    this.scannedBarcodeTypeId,
    this.sourceAction,
  });

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

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    _valueController.text = (widget.scannedBarcode ?? widget.product['barcode'] ?? "").toString();
    _weightController.text = (widget.product['weight'] ?? "").toString();

    if (widget.scannedBarcodeTypeId != null) {
      _selectedBarcodeType = widget.scannedBarcodeTypeId.toString();
    } else if (widget.product['barcode_type_id'] != null) {
      _selectedBarcodeType = widget.product['barcode_type_id'].toString();
    }

    if (widget.product['weight_unit_id'] != null) {
      _selectedWeightUnit = widget.product['weight_unit_id'].toString();
    }

    if (widget.product['cbm_unit_id'] != null) {
      _isCbmChecked = true;
      _selectedDimUnit = widget.product['cbm_unit_id'].toString();
      _lengthController.text = (widget.product['cbm_length'] ?? "").toString();
      _widthController.text = (widget.product['cbm_width'] ?? "").toString();
      _heightController.text = (widget.product['cbm_height'] ?? "").toString();
    }
    
    _valueController.addListener(() => setState(() {}));
    _weightController.addListener(() => setState(() {}));
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

  // --- BARCODE GENERATION LOGIC ---
  void _generateUniqueBarcode() {
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    String newValue = "";

    if (_selectedBarcodeType == '1') {
      // EAN-13: Requires 12 digits (the 13th is a checksum calculated by the widget)
      newValue = timestamp.substring(timestamp.length - 12);
    } else if (_selectedBarcodeType == '2') {
      // Code 128: Alphanumeric. Using a prefix + short timestamp
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
    try {
      final res = await http.get(Uri.parse('http://192.168.0.143:8056/items/barcode_type'));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body)['data'];
        final Map<String, String> fetchedTypes = {'0': 'N/A'};
        for (var item in data) {
          if (item['is_active'] == 1) fetchedTypes[item['id'].toString()] = item['name'].toString();
        }
        if (mounted) setState(() => _barcodeTypes = fetchedTypes);
      }
    } catch (_) {}
  }

  Future<void> _fetchWeightUnits() async {
    try {
      final res = await http.get(Uri.parse('http://192.168.0.143:8056/items/weight_unit'));
      if (res.statusCode == 200) {
        final List data = json.decode(res.body)['data'];
        final Map<String, String> fetchedUnits = {'0': 'N/A'};
        for (var item in data) {
          if (item['is_active'] == 1) fetchedUnits[item['id'].toString()] = item['code'].toString();
        }
        if (mounted) setState(() => _weightUnits = fetchedUnits);
      }
    } catch (_) {}
  }

  // --- VALIDATION ---
  String? get _weightError {
    if (_weightController.text.isEmpty) return null;
    final val = double.tryParse(_weightController.text);
    if (val == null) return "Invalid numeric value";
    if (val <= 0) return "Weight must be > 0";
    return null;
  }

  String? get _unitError {
    if (_weightController.text.isNotEmpty && _selectedWeightUnit == '0') return "Select unit";
    return null;
  }

  bool get _isFormValid {
    if (_selectedBarcodeType == '0' || _valueController.text.trim().isEmpty) return false;
    if (_weightError != null || _unitError != null) return false;
    return true;
  }

  // --- SAVE ACTION ---
  Future<void> _saveProduct() async {
    setState(() => _isSaving = true);
    try {
      final id = widget.product['product_id'] ?? widget.product['id'];
      final body = {
        'barcode': _valueController.text.trim(),
        'barcode_type_id': int.parse(_selectedBarcodeType),
        'weight': double.tryParse(_weightController.text) ?? 0.0,
        'weight_unit_id': int.parse(_selectedWeightUnit),
        if (_isCbmChecked) ...{
          'cbm_length': double.tryParse(_lengthController.text) ?? 0.0,
          'cbm_width': double.tryParse(_widthController.text) ?? 0.0,
          'cbm_height': double.tryParse(_heightController.text) ?? 0.0,
          'cbm_unit_id': int.parse(_selectedDimUnit),
        }
      };
      
      final response = await http.patch(
        Uri.parse('http://192.168.0.143:8056/items/products/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode <= 204 && mounted) {
        Navigator.pop(context, {
          'saved': true,
          'barcode': _valueController.text.trim(),
          'is_scanned': widget.scannedBarcode != null,
          'is_rescan': widget.sourceAction == 'rescan',
          'is_regenerated': widget.sourceAction == 'regenerate',
        });
      }
    } catch (e) { debugPrint("🔴 Save Error: $e"); } 
    finally { if (mounted) setState(() => _isSaving = false); }
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
            Text(widget.product['product_name'] ?? 'Product Generator', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
              _appBarBadge("SKU: ${widget.product['product_code'] ?? 'N/A'}"),
              const SizedBox(width: 8),
              _appBarBadge("ID: ${_getProductId(widget.product)}"),
            ]),
          ],
        ),
        backgroundColor: Colors.blue.shade900,
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
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _valueController, 
                          decoration: _inputDecoration("Barcode Value", Icons.edit_note)
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 255, 0, 128),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _selectedBarcodeType == '0' ? null : _generateUniqueBarcode,
                        child: const Icon(Icons.auto_fix_high),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: "Product Specifications",
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
                    activeColor: Colors.blue.shade900,
                    onChanged: (val) => setState(() => _isCbmChecked = val!),
                  ),
                  if (_isCbmChecked) ...[
                    Row(
                      children: [
                        _buildDimField(_lengthController, "L"),
                        _buildDimField(_widthController, "W"),
                        _buildDimField(_heightController, "H"),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: DropdownButtonFormField<String>(
                            value: _selectedDimUnit,
                            decoration: const InputDecoration(isDense: true, labelText: "Unit"),
                            items: _dimUnits.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                            onChanged: (val) => setState(() => _selectedDimUnit = val!),
                          ),
                        ),
                      ],
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildPreviewSection(),
            const SizedBox(height: 32),
            if (_isSaving) const Center(child: CircularProgressIndicator())
            else Row(
                children: [
                  Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), foregroundColor: Colors.blue.shade900), onPressed: _printBarcode, icon: const Icon(Icons.print), label: const Text("PRINT"))),
                  const SizedBox(width: 16),
                  Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), elevation: 2), onPressed: _isFormValid ? _saveProduct : null, icon: const Icon(Icons.save), label: const Text("SAVE PRODUCT"))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade900)), const SizedBox(height: 16), child]),
    );
  }

  InputDecoration _inputDecoration(String label, IconData? icon, {String? hint, String? error}) {
    return InputDecoration(
      labelText: label, hintText: hint, errorText: error,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true, fillColor: const Color(0xFFF1F5F9), isDense: true,
    );
  }

  Widget _buildDimField(TextEditingController controller, String hint) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextField(
          controller: controller, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: hint, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    return Column(children: [
      const Text("LIVE BARCODE PREVIEW", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
      const SizedBox(height: 12),
      Container(
        width: double.infinity, padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.shade100)),
        child: Column(children: [
          if (_valueController.text.isNotEmpty && _selectedBarcodeType != '0')
            BarcodeWidget(
              barcode: _selectedBarcodeType == '1' ? Barcode.ean13() : Barcode.code128(), 
              data: _valueController.text, 
              width: double.infinity, 
              height: 100, 
              drawText: true, 
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)
            )
          else const Text("Waiting for valid data...", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
        ]),
      ),
    ]);
  }

  Widget _appBarBadge(String text) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)), child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.white)));
  }

  dynamic _getProductId(Map<String, dynamic> p) {
    for (var k in ['product_id', 'id', 'itemId', 'item_id']) { if (p[k] != null) return p[k]; }
    return "N/A";
  }

  Future<void> _printBarcode() async {
    if (_valueController.text.isEmpty || _selectedBarcodeType == '0') return;

    // 1. Show an improved Bottom Sheet for a better Mobile UI
    final bool? withDetails = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar for visual cue
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
            ),
            const SizedBox(height: 20),
            Text(
              "Print Options",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
            ),
            const SizedBox(height: 8),
            const Text("Choose your layout style for the label:", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            
            // Option 1: Barcode Only
            _buildPrintOption(
              context,
              icon: Icons.qr_code,
              title: "Barcode Only",
              subtitle: "Minimalist: Name & Barcode number",
              onTap: () => Navigator.pop(context, false),
            ),
            const SizedBox(height: 12),
            
            // Option 2: Full Details
            _buildPrintOption(
              context,
              icon: Icons.receipt_long,
              title: "With Details",
              subtitle: "Full Specs: SKU, Weight, and CBM",
              onTap: () => Navigator.pop(context, true),
              isPrimary: true,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    if (withDetails == null) return;

    // --- PDF GENERATION LOGIC REMAINS UNCHANGED ---
    try {
      final pw.Document pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                widget.product['product_name']?.toString().toUpperCase() ?? 'PRODUCT',
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
                    pw.Text(widget.product['product_code'] ?? 'N/A', style: const pw.TextStyle(fontSize: 9)),
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
                      pw.Text(
                        "${_lengthController.text}x${_widthController.text}x${_heightController.text} ${_dimUnits[_selectedDimUnit]}",
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ],
                pw.SizedBox(height: 5),
                pw.Divider(thickness: 0.5),
              ],
            ],
          );
        },
      ));
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      debugPrint('🔴 Print Error: $e');
    }
  }

  // Helper Widget for the UI Options
  Widget _buildPrintOption(BuildContext context, {
    required IconData icon, 
    required String title, 
    required String subtitle, 
    required VoidCallback onTap,
    bool isPrimary = false
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.blue.shade50 : Colors.grey.shade50,
          border: Border.all(color: isPrimary ? Colors.blue.shade200 : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, color: isPrimary ? Colors.blue.shade900 : Colors.grey.shade700, size: 28),
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