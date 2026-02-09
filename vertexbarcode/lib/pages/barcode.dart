import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraScannerPage extends StatefulWidget {
  final String productName;
  final String oldBarcode;

  // Added constructor to receive product details
  const CameraScannerPage({
    super.key,
    required this.productName,
    required this.oldBarcode,
  });

  @override
  State<CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScannerPageState extends State<CameraScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Barcode'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Camera / Scanner
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (_hasScanned) return;

                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String code = barcodes.first.rawValue ?? "";
                  if (code.isNotEmpty) {
                    _hasScanned = true;
                    Navigator.pop(context, code);
                  }
                }
              },
            ),
          ),

          // Product Info Card
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  const BoxShadow(color: Colors.black26, blurRadius: 10),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "UPDATING BARCODE FOR:",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Text(
                    widget.productName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Current: ${widget.oldBarcode}",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),

          // Visual Overlay
          Center(
            child: Container(
              width: 260,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "SCAN NEW BARCODE",
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      backgroundColor: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom manual entry affordance (always available)
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.9),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    // open a dialog for manual input
                    final manual = await showDialog<String?>(
                      context: context,
                      builder: (context) {
                        final t = TextEditingController();
                        return AlertDialog(
                          title: const Text('Enter Barcode Manually'),
                          content: TextField(
                            controller: t,
                            decoration: const InputDecoration(
                              hintText: 'Barcode',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(context, t.text.trim()),
                              child: const Text('Save'),
                            ),
                          ],
                        );
                      },
                    );

                    if (manual != null && manual.isNotEmpty) {
                      Navigator.pop(context, manual);
                    }
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Enter Manually'),
                ),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.9),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    // toggle flash as small helpful action
                    try {
                      await _controller.toggleTorch();
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Toggle Flash'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
