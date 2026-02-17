import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PrintScreen extends StatefulWidget {
  final List allProducts;

  const PrintScreen({super.key, required this.allProducts});

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  List filteredToPrint = [];
  List displayedProducts = [];
  Set<int> selectedIndices = {};
  final TextEditingController _searchController = TextEditingController();
  
  // Map to store ID -> Name relationship (e.g., {1: "EAN-13", 2: "Code 128"})
  Map<int, String> barcodeTypeNames = {};

  @override
  void initState() {
    super.initState();
    _fetchBarcodeTypes(); // Fetch types from API
    filteredToPrint = widget.allProducts.where((p) {
      final barcode = (p['barcode'] ?? "").toString().trim();
      final sku = (p['product_code'] ?? "").toString().trim();
      return barcode.isNotEmpty && sku.isNotEmpty;
    }).toList();
    displayedProducts = List.from(filteredToPrint);
  }

  Future<void> _fetchBarcodeTypes() async {
    try {
      final response = await http.get(Uri.parse('http://192.168.0.143:8056/items/barcode_type'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List typesList = responseData['data'] ?? [];
        
        setState(() {
          barcodeTypeNames = {
            for (var item in typesList) item['id'] as int : item['name'].toString()
          };
        });
      }
    } catch (e) {
      debugPrint("Error fetching barcode types: $e");
    }
  }

  void _runFilter(String query) {
    setState(() {
      if (query.isEmpty) {
        displayedProducts = filteredToPrint;
      } else {
        final searchLower = query.toLowerCase();
        displayedProducts = filteredToPrint.where((product) {
          final name = (product['product_name'] ?? "").toString().toLowerCase();
          final id = (product['product_id'] ?? "").toString().toLowerCase();
          final barcode = (product['barcode'] ?? "").toString().toLowerCase();
          final sku = (product['product_code'] ?? "").toString().toLowerCase();
          return name.contains(searchLower) || id.contains(searchLower) || barcode.contains(searchLower) || sku.contains(searchLower);
        }).toList();
      }
    });
  }

  void _toggleSelection(dynamic item) {
    final masterIndex = filteredToPrint.indexOf(item);
    setState(() {
      if (selectedIndices.contains(masterIndex)) {
        selectedIndices.remove(masterIndex);
      } else {
        selectedIndices.add(masterIndex);
      }
    });
  }

  Future<void> _handlePrint() async {
    if (selectedIndices.isEmpty) return;

    // 1. Show the modern Bottom Sheet for selection
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
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
            ),
            const SizedBox(height: 20),
            Text(
              "Batch Print Options",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
            ),
            const SizedBox(height: 8),
            Text("Print ${selectedIndices.length} labels in A4 grid format:", 
              style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            
            _buildPrintOption(
              context,
              icon: Icons.qr_code,
              title: "Barcode Only",
              subtitle: "Minimalist: Name, Barcode & Type",
              onTap: () => Navigator.pop(context, false),
            ),
            const SizedBox(height: 12),
            
            _buildPrintOption(
              context,
              icon: Icons.receipt_long,
              title: "With Details",
              subtitle: "Full Specs: SKU, Weight, and Dimensions",
              onTap: () => Navigator.pop(context, true),
              isPrimary: true,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    if (withDetails == null) return;

    // 2. Proceed to PDF Generation
    await Printing.layoutPdf(
      name: 'batch_labels_${withDetails ? "full" : "basic"}',
      onLayout: (PdfPageFormat format) async {
        final doc = pw.Document();
        final List selectedItems = selectedIndices.map((i) => filteredToPrint[i]).toList();

        for (var i = 0; i < selectedItems.length; i += 10) {
          final chunk = selectedItems.sublist(i, i + 10 > selectedItems.length ? selectedItems.length : i + 10);

          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(20),
              build: (pw.Context context) {
                return pw.GridView(
                  crossAxisCount: 2,
                  childAspectRatio: .5, 
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: chunk.map((item) {
                    final String barcode = item['barcode'].toString();
                    final String name = item['product_name'] ?? "Unknown";
                    final String sku = item['product_code'] ?? "N/A";
                    
                    final int typeId = int.tryParse(item['barcode_type_id']?.toString() ?? "0") ?? 0;
                    final String barcodeType = barcodeTypeNames[typeId] ?? "CODE128";
                    
                    final String weight = "${item['weight'] ?? '0'} ${item['weight_unit'] ?? ''}";
                    final String cbmUnit = item['cbm_unit']?['code'] ?? 'cm';
                    final String dims = "${item['cbm_length'] ?? '0'}x${item['cbm_width'] ?? '0'}x${item['cbm_height'] ?? '0'} $cbmUnit";

                    return pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          // Header Section
                          pw.Column(
                            children: [
                              pw.Text(name.toUpperCase(), 
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                                  maxLines: 1, textAlign: pw.TextAlign.center),
                              pw.SizedBox(height: 2),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text("SKU: $sku", style: const pw.TextStyle(fontSize: 6)),
                                  pw.Text("Type: $barcodeType", style: const pw.TextStyle(fontSize: 6)),
                                ],
                              ),
                            ],
                          ),

                          // Metadata Section (Only if withDetails is true)
                          if (withDetails) ...[
                            pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text("WEIGHT:", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                                pw.Text(weight, style: const pw.TextStyle(fontSize: 6)),
                              ],
                            ),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text("DIMS:", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                                pw.Text(dims, style: const pw.TextStyle(fontSize: 6)),
                              ],
                            ),
                          ],

                          // Barcode Section
                          pw.Expanded(
                            child: pw.Center(
                              child: pw.BarcodeWidget(
                                barcode: barcodeType.contains("EAN") ? pw.Barcode.ean13() : pw.Barcode.code128(),
                                data: barcode,
                                drawText: true,
                               textStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                                width: 140,
                                height: 60,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          );
        }
        return doc.save();
      },
    );
  }

  // Helper Widget for the UI Options (Must be added to PrintScreen class)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        title: const Text("Batch Printing", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                if (selectedIndices.length == filteredToPrint.length) {
                  selectedIndices.clear();
                } else {
                  selectedIndices = List.generate(filteredToPrint.length, (i) => i).toSet();
                }
              });
            },
            child: Text(selectedIndices.length == filteredToPrint.length ? "DESELECT ALL" : "SELECT ALL", style: const TextStyle(color: Colors.white, fontSize: 12)),
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _runFilter,
              decoration: InputDecoration(
                hintText: "Search Name, SKU, ID, Barcode...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty 
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _runFilter(""); }) 
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.blue.shade50,
            child: Text("${selectedIndices.length} items selected for printing", style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Expanded(
            child: displayedProducts.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: displayedProducts.length,
                    itemBuilder: (context, index) {
                      final item = displayedProducts[index];
                      final masterIdx = filteredToPrint.indexOf(item);
                      final isSelected = selectedIndices.contains(masterIdx);
                      
                      // Lookup barcode type name locally
                      final int typeId = int.tryParse(item['barcode_type_id']?.toString() ?? "0") ?? 0;
                      final String typeDisplay = barcodeTypeNames[typeId] ?? "ID: $typeId";

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isSelected ? Colors.blue.shade900 : Colors.grey.shade200, width: isSelected ? 1.5 : 1),
                        ),
                        child: CheckboxListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          title: Text(item['product_name'] ?? "Unnamed", style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Wrap(
                            spacing: 6,
                            children: [
                              _miniBadge("SKU: ${item['product_code']}"),
                              _miniBadge("BC: ${item['barcode']}"),
                              _miniBadge("TYPE: $typeDisplay"), // Displays the fetched name
                              if (item['product_id'] != null) _miniBadge("ID: ${item['product_id']}"),
                            ],
                          ),
                          value: isSelected,
                          activeColor: Colors.blue.shade900,
                          onChanged: (val) => _toggleSelection(item),
                          controlAffinity: ListTileControlAffinity.trailing,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: selectedIndices.isEmpty ? null : _handlePrint,
          icon: const Icon(Icons.print_rounded),
          label: Text("PRINT ${selectedIndices.length} BARCODES"),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.search_off_rounded, size: 64, color: Colors.grey), const SizedBox(height: 16), const Text("No products found.", style: TextStyle(color: Colors.grey))]));
  }

  Widget _miniBadge(String text) {
    return Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)), child: Text(text, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontFamily: 'monospace')));
  }
}