import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScannerPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const CameraScannerPage({super.key, required this.product});

  @override
  State<CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<CameraScannerPage> {
  // Controller set to detect common 1D formats but ignore 2D (QR/DataMatrix)
  final MobileScannerController controller = MobileScannerController(
    formats: [BarcodeFormat.ean13, BarcodeFormat.code128, BarcodeFormat.ean8],
    detectionSpeed: DetectionSpeed.normal,
  );

  bool isScanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Checks if the scanned barcode already exists in the database 
  /// for a different product code.
  Future<Map<String, dynamic>?> _findDuplicate(String barcode) async {
    if (barcode.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.parse('http://192.168.0.143:8056/items/products'),
      );
      if (res.statusCode == 200) {
        final List data = json.decode(res.body)['data'];
        final String currSku = (widget.product['product_code'] ?? '').toString();
        
        for (var p in data) {
          final String existing = (p['barcode'] ?? '').toString().trim();
          final String otherSku = (p['product_code'] ?? '').toString();
          
          // If the barcode matches but the product code is different, it's a duplicate
          if (existing == barcode && otherSku != currSku) {
            return Map<String, dynamic>.from(p);
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking duplicate: $e");
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
              widget.product['product_name'] ?? 'Scan Barcode',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              "Current: ${widget.product['barcode'] ?? 'NONE'}",
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

                  // 1. Check duplicate against API
                  final dup = await _findDuplicate(value);
                  final String currSku = (widget.product['product_code'] ?? '').toString();
                  
                  if (dup != null && (dup['product_code'] ?? '').toString() != currSku) {
                    // Return duplicate info to caller so it can show the warning
                    if (mounted) {
                      Navigator.pop(context, {
                        'duplicate': dup,
                        'value': value,
                      });
                    }
                    return;
                  }

                  // 2. Map MobileScanner BarcodeFormat to your internal database ID
                  int typeId = 0; // Default 0 => N/A
                  final fmt = barcode.format;
                  if (fmt == BarcodeFormat.ean13) {
                    typeId = 1;
                  } else if (fmt == BarcodeFormat.code128) {
                    typeId = 2;
                  }

                  // 3. Accept scan and return valid data
                  if (mounted) {
                    setState(() => isScanned = true);
                    Navigator.pop(context, {
                      'value': value, 
                      'type_id': typeId
                    });
                  }
                  break;
                }
              }
            },
          ),
          
          // Scanner Overlay UI (Square target area)
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Stack(
                children: [
                  ScanningLine(),
                ],
              ),
            ),
          ),

          // Instructions Label
          Positioned(
            top: MediaQuery.of(context).size.height * 0.2,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Align barcode within the frame",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),

          // Flashlight Toggle
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.black54,
                child: IconButton(
                  color: Colors.white,
                  icon: ValueListenableBuilder<TorchState?>(
                    valueListenable: controller.torchState,
                    builder: (context, state, child) {
                      return Icon(
                        state == TorchState.on ? Icons.flash_on : Icons.flash_off,
                        size: 28,
                      );
                    },
                  ),
                  onPressed: () => controller.toggleTorch(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple red line that moves up and down to simulate a laser scanner
class ScanningLine extends StatefulWidget {
  const ScanningLine({super.key});

  @override
  State<ScanningLine> createState() => _ScanningLineState();
}

class _ScanningLineState extends State<ScanningLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
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
          top: _controller.value * 248, // Slightly less than container height
          left: 5,
          right: 5,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}