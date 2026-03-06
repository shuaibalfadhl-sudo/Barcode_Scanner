import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart'; 

import 'barcode_generator.dart'; 

class CameraScannerPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const CameraScannerPage({super.key, required this.product});

  @override
  State<CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<CameraScannerPage> {
  final MobileScannerController controller = MobileScannerController(
    formats: [BarcodeFormat.ean13, BarcodeFormat.code128, BarcodeFormat.ean8, BarcodeFormat.itf],
    detectionSpeed: DetectionSpeed.normal,
  );

  bool isScanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _findDuplicate(String barcode) async {
    if (barcode.isEmpty) return null;
    
    List data = [];
    final prefs = await SharedPreferences.getInstance();
    
    final bool isBundle = widget.product.containsKey('bundle_name');
    final String url = isBundle 
        ? 'http://192.168.0.143:8056/items/product_bundles?limit=-1'
        : 'http://192.168.0.143:8091/items/products?limit=-1';
    final String cacheKey = isBundle ? 'cached_bundles_scanner' : 'cached_products_scanner';
    final String skuKey = isBundle ? 'bundle_sku' : 'product_code';
    
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        data = json.decode(res.body)['data'];
        await prefs.setString(cacheKey, json.encode(data));
      }
    } catch (e) {
      debugPrint("Network error checking duplicate: $e");
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        data = json.decode(cached);
      }
    }

    if (data.isNotEmpty) {
      final String currSku = (widget.product[skuKey] ?? widget.product['product_code'] ?? '').toString();
      
      for (var p in data) {
        final String existing = (p['barcode_value'] ?? p['barcode'] ?? '').toString().trim();
        final String otherSku = (p[skuKey] ?? p['product_code'] ?? '').toString();
        
        if (existing == barcode && existing.isNotEmpty && otherSku != currSku) {
          return Map<String, dynamic>.from(p);
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product['product_name'] ?? widget.product['bundle_name'] ?? 'Scan Barcode',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              "Current: ${widget.product['barcode_value'] ?? widget.product['barcode'] ?? 'NONE'}",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) async {
              if (isScanned) return;

              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  final String value = barcode.rawValue!;
                  debugPrint("🔍 SCANNER: Barcode detected: $value");
                  
                  setState(() => isScanned = true);

                  // 1. Check duplicate
                  final dup = await _findDuplicate(value);
                  final String currSku = (widget.product['bundle_sku'] ?? widget.product['product_code'] ?? '').toString();

                  if (dup != null && (dup['bundle_sku'] ?? dup['product_code'] ?? '').toString() != currSku) {
                    if (mounted) {
                      await showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          title: const Text("Barcode Already Used"),
                          content: Text(
                            "This barcode ($value) is already assigned to:\n\n"
                            "Name: ${dup['product_name'] ?? dup['bundle_name']}\n"
                            "Code: ${dup['product_code'] ?? dup['bundle_sku']}"
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                setState(() => isScanned = false);
                              },
                              child: const Text("TRY AGAIN"),
                            ),
                          ],
                        ),
                      );
                    }
                    return; 
                  }

                  // 2. Map BarcodeFormat
                  int typeId = 0;
                  final fmt = barcode.format;
                  if (fmt == BarcodeFormat.ean13) typeId = 1;
                  else if (fmt == BarcodeFormat.code128) typeId = 2;

                  // 3. --- DIRECT REDIRECT TO GENERATOR ---
                  if (mounted) {
                    final String existingBarcode = (widget.product['barcode_value'] ?? widget.product['barcode'] ?? '').toString().trim();
                    final String effectiveAction = existingBarcode.isNotEmpty ? 'rescan' : 'scan';

                    debugPrint("🚀 SCANNER: Pushing to Generator Screen...");
                    final genResult = await Navigator.push(
                      context, 
                      MaterialPageRoute(
                        builder: (context) => BarcodeGeneratorScreen(
                          product: widget.product,
                          scannedBarcode: value,
                          scannedBarcodeTypeId: typeId,
                          sourceAction: effectiveAction,
                        ),
                      )
                    );

                    // 4. --- RETURN TO INDEX WITH REINFORCED DATA ---
                    if (genResult != null && genResult is Map && genResult['saved'] == true) {
                      debugPrint("✅ SCANNER: Generator saved successfully. Popping scanner with data.");
                      
                      // We add a specific 'is_scanned' flag here to ensure 
                      // index.dart recognizes this as a camera scan for the history log
                      final Map<String, dynamic> finalData = Map<String, dynamic>.from(genResult);
                      finalData['is_scanned'] = true; 
                      
                      if (mounted) {
                        Navigator.pop(context, finalData);
                      }
                    } else {
                      debugPrint("⚠️ SCANNER: Generator was cancelled or failed. Resuming scanner.");
                      setState(() => isScanned = false);
                    }
                  }
                  break;
                }
              }
            },
          ),
          
          // Scanning UI Overlays
          Center(
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Stack(children: [ScanningLine()]),
            ),
          ),
          // ... (Rest of your UI widgets like the align text and flash toggle)
        ],
      ),
    );
  }
}

// ... (ScanningLine widget stays the same)

class ScanningLine extends StatefulWidget {
  const ScanningLine({super.key});
  @override
  State<ScanningLine> createState() => _ScanningLineState();
}

class _ScanningLineState extends State<ScanningLine> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: _controller.value * 248,
          left: 5, right: 5,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.6), blurRadius: 6, spreadRadius: 2)],
            ),
          ),
        );
      },
    );
  }
}