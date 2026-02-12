import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:http/http.dart' as http;

class BarcodeGeneratorScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final String? scannedBarcode;
  final int? scannedBarcodeTypeId;
  final String? sourceAction;
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

  // '0' will represent N/A or Null state
  String _selectedBarcodeType = '0';
  String _selectedWeightUnit = '0'; // Default to N/A (ID: 0)
  String _selectedDimUnit = '2'; // Default to CM (ID: 2)
  bool _isCbmChecked = false;
  bool _isSaving = false;

  // Mapping for UI Display - Added '0' as N/A
  final Map<String, String> _barcodeTypes = {
    '0': 'N/A',
    '1': 'EAN-13',
    '2': 'Code 128',
  };

  final Map<String, String> _weightUnits = {
    '0': 'N/A',
    '1': 'G',
    '2': 'KG',
    '3': 'LB',
    '4': 'OZ',
  };

  final Map<String, String> _dimUnits = {
    '1': 'MM',
    '2': 'CM',
    '3': 'M',
    '4': 'IN',
    '5': 'FT',
  };

  @override
  void initState() {
    super.initState();

    // 1. Set Barcode Value (prefer scanned value if present)
    final existingBarcode =
        (widget.scannedBarcode ?? widget.product['barcode'] ?? "").toString();
    _valueController.text = existingBarcode;

    // 2. Set Weight
    _weightController.text = (widget.product['product_weight'] ?? "")
        .toString();

    // 3. Set Barcode Type (prefer scanned detection, else product value)
    if (widget.scannedBarcodeTypeId != null) {
      _selectedBarcodeType = widget.scannedBarcodeTypeId.toString();
    } else if (widget.product['barcode_type_id'] != null) {
      _selectedBarcodeType = widget.product['barcode_type_id'].toString();
    } else {
      _selectedBarcodeType = '0'; // Default to N/A
    }

    // 4. Set Units
    if (widget.product['weight_unit_id'] != null) {
      _selectedWeightUnit = widget.product['weight_unit_id'].toString();
    }

    // 5. Set CBM if exists
    if (widget.product['cbm_unit_id'] != null) {
      _isCbmChecked = true;
      _selectedDimUnit = widget.product['cbm_unit_id'].toString();
      _lengthController.text = (widget.product['cbm_length'] ?? "").toString();
      _widthController.text = (widget.product['cbm_width'] ?? "").toString();
      _heightController.text = (widget.product['cbm_height'] ?? "").toString();
    }
  }

  Future<Map<String, dynamic>?> _findDuplicate(String barcode) async {
    if (barcode.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('http://192.168.0.143:8056/items/products'),
      );
      if (res.statusCode == 200) {
        final List data = json.decode(res.body)['data'];
        final String currSku = (widget.product['product_code'] ?? '')
            .toString();
        for (var p in data) {
          final String existing = (p['barcode'] ?? '').toString().trim();
          final String otherSku = (p['product_code'] ?? '').toString();
          if (existing == barcode && otherSku != currSku) {
            return Map<String, dynamic>.from(p);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool get _isFormValid {
    String val = _valueController.text.trim();

    // If Barcode Type is N/A, we can't generate a barcode, so form is invalid for "Saving" a barcode
    if (_selectedBarcodeType == '0') return false;
    if (val.isEmpty) return false;

    // EAN-13 validation
    if (_selectedBarcodeType == '1') {
      if (val.length < 12 || val.length > 13 || double.tryParse(val) == null)
        return false;
    }

    if (_isCbmChecked) {
      double l = double.tryParse(_lengthController.text) ?? 0;
      double w = double.tryParse(_widthController.text) ?? 0;
      double h = double.tryParse(_heightController.text) ?? 0;
      return l > 0 && w > 0 && h > 0;
    }
    // Require product weight > 0 before allowing save
    double weight = double.tryParse(_weightController.text) ?? 0;
    if (weight <= 0) return false;
    return true;
  }

  Future<void> _saveProduct() async {
    // Enforce weight requirement
    double weight = double.tryParse(_weightController.text) ?? 0;
    if (weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a valid product weight before saving."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Check for duplicate barcode on other products before saving
    try {
      final String newVal = _valueController.text.trim();
      final dup = await _findDuplicate(newVal);
      if (dup != null) {
        if (mounted) {
          setState(() => _isSaving = false);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Column(
                children: [
                  Icon(Icons.report_problem, color: Colors.red, size: 60),
                  SizedBox(height: 10),
                  Text(
                    "BARCODE TAKEN",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("This barcode is already assigned to:"),
                  const SizedBox(height: 10),
                  Text(
                    dup['product_name'] ?? "Unknown",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const Divider(height: 30),
                  Text(
                    "Code: $newVal",
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              actions: [
                Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("GO BACK"),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }
    } catch (e) {
      // ignore lookup errors and continue to attempt save
    }

    final id = widget.product['product_id'] ?? widget.product['id'];
    final url = Uri.parse('http://192.168.0.143:8056/items/products/$id');

    final Map<String, dynamic> body = {
      'barcode': _valueController.text.trim(),
      'barcode_type_id': int.parse(_selectedBarcodeType),
      'product_weight': double.tryParse(_weightController.text) ?? 0,
    };

    // Only include weight_unit_id when a valid unit is selected (not N/A)
    if (_selectedWeightUnit != '0') {
      body['weight_unit_id'] = int.parse(_selectedWeightUnit);
    }

    if (_isCbmChecked) {
      body.addAll({
        'cbm_length': double.tryParse(_lengthController.text),
        'cbm_width': double.tryParse(_widthController.text),
        'cbm_height': double.tryParse(_heightController.text),
        'cbm_unit_id': int.parse(_selectedDimUnit),
      });
    }

    try {
      final response = await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Product updated successfully!"),
              backgroundColor: Colors.green,
            ),
          );
          // Determine rescan/regenerate based on sourceAction or product state
          final bool hadBarcode = (widget.product['barcode'] ?? "")
              .toString()
              .trim()
              .isNotEmpty;
          final bool isScanned = widget.scannedBarcode != null;
          final bool isRescan =
              widget.sourceAction == 'rescan' || (isScanned && hadBarcode);
          final bool isRegenerated = widget.sourceAction == 'regenerate';

          // Return structured result so caller can record history appropriately
          Navigator.pop(context, {
            'saved': true,
            'barcode': _valueController.text.trim(),
            'is_scanned': isScanned,
            'is_rescan': isRescan,
            'is_regenerated': isRegenerated,
          });
        }
      } else {
        throw "Server error: ${response.statusCode}";
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(
                "Generate for ${widget.product['product_name'] ?? 'Product'}",
              ),
            ),
            if (widget.sourceAction != null || widget.scannedBarcode != null)
              Builder(
                builder: (_) {
                  String label = 'SCANNED';
                  Color bg = Colors.green;
                  if (widget.sourceAction == 'rescan') {
                    label = 'RESCAN';
                    bg = Colors.orange;
                  } else if (widget.sourceAction == 'regenerate') {
                    label = 'REGENERATE';
                    bg = Colors.purple;
                  } else if (widget.scannedBarcode != null) {
                    label = 'SCANNED';
                    bg = Colors.green;
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Barcode Type Selection (Includes N/A)
            DropdownButtonFormField<String>(
              value: _selectedBarcodeType,
              decoration: const InputDecoration(
                labelText: "Barcode Type",
                border: OutlineInputBorder(),
              ),
              items: _barcodeTypes.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: e.key == '0' ? Colors.red : Colors.black,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedBarcodeType = val!),
            ),
            const SizedBox(height: 15),

            // 2. Barcode Value Input
            TextField(
              controller: _valueController,
              decoration: InputDecoration(
                labelText: "Barcode Value",
                hintText: _selectedBarcodeType == '1'
                    ? "Enter 12-13 digits"
                    : "Enter text or numbers",
                border: const OutlineInputBorder(),
                suffixIcon: _valueController.text.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          "N/A",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              ),
              onChanged: (val) => setState(() {}),
            ),
            const SizedBox(height: 15),

            // 3. Weight and Unit
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _weightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Weight",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedWeightUnit,
                    decoration: const InputDecoration(
                      labelText: "Unit",
                      border: OutlineInputBorder(),
                    ),
                    items: _weightUnits.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedWeightUnit = val!),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 4. CBM Checkbox and Inputs
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                "Include CBM Dimensions",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              value: _isCbmChecked,
              onChanged: (val) => setState(() => _isCbmChecked = val!),
            ),

            if (_isCbmChecked) ...[
              Row(
                children: [
                  _buildDimField(_lengthController, "L"),
                  _buildDimField(_widthController, "W"),
                  _buildDimField(_heightController, "H"),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 80,
                    child: DropdownButtonFormField<String>(
                      value: _selectedDimUnit,
                      decoration: const InputDecoration(labelText: "Unit"),
                      items: _dimUnits.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedDimUnit = val!),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 30),

            // 5. The Barcode Preview
            Center(
              child: Column(
                children: [
                  const Text(
                    "PREVIEW",
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_valueController.text.isNotEmpty &&
                      _selectedBarcodeType != '0' &&
                      _isFormValid)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: BarcodeWidget(
                        barcode: _selectedBarcodeType == '1'
                            ? Barcode.ean13()
                            : Barcode.code128(),
                        data: _valueController.text,
                        width: 250,
                        height: 80,
                        drawText: true,
                      ),
                    )
                  else
                    Container(
                      height: 100,
                      width: 250,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          _selectedBarcodeType == '0'
                              ? "Select a Barcode Type"
                              : "Invalid or Empty Data",
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 6. Action Buttons
            if (_isSaving)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text("CANCEL"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade900,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isFormValid ? _saveProduct : null,
                      icon: const Icon(Icons.save),
                      label: const Text("SAVE TO DB"),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimField(TextEditingController controller, String hint) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          onChanged: (val) => setState(() {}),
          decoration: InputDecoration(
            labelText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
