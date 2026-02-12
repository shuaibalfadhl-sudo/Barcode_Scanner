import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'barcode.dart';
import 'barcode_generator.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  // Data Lists
  List allProducts = [];
  List filteredProducts = [];
  List brands = [];
  List categories = [];
  List<Map<String, dynamic>> recentScans = [];

  // State Management
  bool isLoading = true;
  String searchQuery = "";
  String? selectedBrandId;
  String? selectedCategoryId;

  // Scroll Management
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadStoredHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // --- SCROLL & HISTORY PERSISTENCE ---

  void _onScroll() {
    setState(() {
      _showBackToTop = _scrollController.offset > 300;
    });
  }

  Future<void> _saveHistoryToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = json.encode(
      recentScans.map((item) {
        var tempMap = Map<String, dynamic>.from(item);
        if (tempMap['time'] is DateTime) {
          tempMap['time'] = (tempMap['time'] as DateTime).toIso8601String();
        }
        return tempMap;
      }).toList(),
    );
    await prefs.setString('barcode_history_key', encodedData);
  }

  Future<void> _loadStoredHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyString = prefs.getString('barcode_history_key');
    if (historyString != null) {
      final List decodedList = json.decode(historyString);
      setState(() {
        recentScans = decodedList
            .map(
              (item) => {
                'product_name': item['product_name'],
                'barcode': item['barcode'],
                'is_scanned': item['is_scanned'] ?? false,
                'is_rescan': item['is_rescan'] ?? false,
                'is_generated': item['is_generated'] ?? false,
                'is_regenerated': item['is_regenerated'] ?? false,
                'time': DateTime.tryParse(item['time'] ?? '') ?? DateTime.now(),
                'original_data': item['original_data'],
              },
            )
            .toList();
      });
    }
  }

  // --- API & FILTERING ---

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      await Future.wait([_fetchProducts(), _fetchBrands(), _fetchCategories()]);
    } catch (e) {
      _showSnackBar('Init Error: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchProducts() async {
    final response = await http.get(
      Uri.parse('http://192.168.0.143:8056/items/products'),
    );
    if (response.statusCode == 200) {
      List data = json.decode(response.body)['data'];
      data.sort((a, b) {
        final bool hasA = (a['barcode'] ?? "").toString().trim().isNotEmpty;
        final bool hasB = (b['barcode'] ?? "").toString().trim().isNotEmpty;
        if (!hasA && hasB) return -1;
        if (hasA && !hasB) return 1;
        return (a['product_name'] ?? "").toString().toLowerCase().compareTo(
          (b['product_name'] ?? "").toString().toLowerCase(),
        );
      });
      allProducts = data;
      _applyFilters();
    }
  }

  Future<void> _fetchBrands() async {
    final res = await http.get(
      Uri.parse('http://192.168.0.143:8056/items/brand'),
    );
    if (res.statusCode == 200)
      setState(() => brands = json.decode(res.body)['data']);
  }

  Future<void> _fetchCategories() async {
    final res = await http.get(
      Uri.parse('http://192.168.0.143:8056/items/categories'),
    );
    if (res.statusCode == 200)
      setState(() => categories = json.decode(res.body)['data']);
  }

  void _applyFilters() {
    setState(() {
      filteredProducts = allProducts.where((p) {
        final query = searchQuery.toLowerCase();
        final name = (p['product_name'] ?? "").toString().toLowerCase();
        final pId = _getProductId(p).toString().toLowerCase();
        final matchesSearch = name.contains(query) || pId.contains(query);

        final String pBrand = (p['product_brand'] ?? "").toString();
        final bool matchesBrand =
            selectedBrandId == null || pBrand == selectedBrandId;
        final String pCategory = (p['product_category'] ?? "").toString();
        final bool matchesCategory =
            selectedCategoryId == null || pCategory == selectedCategoryId;

        return matchesSearch && matchesBrand && matchesCategory;
      }).toList();
    });
  }

  // --- PRODUCT INFO DIALOG ---

  void _showProductDetails(
    Map<String, dynamic> product, {
    Map<String, dynamic>? history,
  }) {
    String getValue(String key) {
      final val = product[key];
      if (val == null ||
          val.toString().trim().isEmpty ||
          val.toString() == "null")
        return "N/A";
      return val.toString();
    }

    String getBarcodeType(dynamic id) {
      if (id.toString() == "1") return "EAN-13";
      if (id.toString() == "2") return "Code 128";
      return "N/A";
    }

    String getWeightUnit(dynamic id) {
      final units = {"1": "G", "2": "KG", "3": "LB", "4": "OZ"};
      return units[id.toString()] ?? "";
    }

    String getCbmUnit(dynamic id) {
      final units = {"1": "MM", "2": "CM", "3": "M", "4": "IN", "5": "FT"};
      return units[id.toString()] ?? "";
    }

    final String sku = getValue('product_code');
    final String prodId = _getProductId(product).toString();
    final bool hasSku = sku != "N/A";
    final String weightUnit = getWeightUnit(product['weight_unit_id']);
    final String cbmUnit = getCbmUnit(product['cbm_unit_id']);

    // If opened from a history item, determine source action for generator display
    String? sourceAction;
    if (history != null) {
      if (history['is_scanned'] == true)
        sourceAction = 'rescan';
      else if (history['is_generated'] == true)
        sourceAction = 'regenerate';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          product['product_name'] ?? 'Product Info',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("ID", prodId, isPrimary: true),
              _detailRow("SKU", sku),
              _detailRow("Barcode", getValue('barcode')),
              _detailRow("BC Type", getBarcodeType(product['barcode_type_id'])),
              const Divider(),
              _detailRow("Weight", "${getValue('product_weight')} $weightUnit"),
              const SizedBox(height: 8),
              const Text(
                "Dimensions (CBM)",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              _detailRow("Length", "${getValue('cbm_length')} $cbmUnit"),
              _detailRow("Width", "${getValue('cbm_width')} $cbmUnit"),
              _detailRow("Height", "${getValue('cbm_height')} $cbmUnit"),
              if (!hasSku)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    "⚠️ Actions disabled: SKU is missing",
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: hasSku
                          ? () async {
                              final BuildContext parentCtx =
                                  _scaffoldKey.currentContext ?? context;
                              Navigator.pop(context);
                              final result = await Navigator.push(
                                parentCtx,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CameraScannerPage(product: product),
                                ),
                              );
                              // If scanner returned a duplicate, show warning here (centered)
                              if (result != null &&
                                  result['duplicate'] != null) {
                                final dup = result['duplicate'];
                                await showGeneralDialog(
                                  context: parentCtx,
                                  barrierDismissible: false,
                                  barrierLabel: 'Duplicate',
                                  transitionDuration: const Duration(
                                    milliseconds: 150,
                                  ),
                                  pageBuilder: (ctx, a1, a2) {
                                    return WillPopScope(
                                      onWillPop: () async => false,
                                      child: AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        title: const Center(
                                          child: Text(
                                            'BARCODE TAKEN',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Center(
                                              child: Text(
                                                dup['product_name'] ??
                                                    'Unknown',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Center(
                                              child: Text(
                                                'SKU: ${dup['product_code'] ?? ''}',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Center(
                                              child: Text(
                                                'Code: ${result['value'] ?? ''}',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          Center(
                                            child: TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx),
                                              child: const Text('OK'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                                return;
                              }

                              if (result != null && result['value'] != null) {
                                final String scannedValue = result['value'];
                                final int? typeId = result['type_id'] is int
                                    ? result['type_id'] as int
                                    : null;

                                // Redirect to generator with prefilled scanned value/type
                                final BuildContext parentCtx2 =
                                    _scaffoldKey.currentContext ?? context;
                                final genResult = await Navigator.push(
                                  parentCtx2,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        BarcodeGeneratorScreen(
                                          product: product,
                                          scannedBarcode: scannedValue,
                                          scannedBarcodeTypeId: typeId,
                                          sourceAction: sourceAction,
                                        ),
                                  ),
                                );

                                // Handle generator save result: generator returns a map with explicit flags
                                if (genResult != null &&
                                    genResult is Map &&
                                    genResult['saved'] == true) {
                                  final String savedCode =
                                      (genResult['barcode'] ?? scannedValue)
                                          .toString();
                                  final bool wasScanned =
                                      genResult['is_scanned'] == true;
                                  final bool rescanFlag =
                                      genResult['is_rescan'] == true;
                                  final bool regenFlag =
                                      genResult['is_regenerated'] == true;

                                  if (regenFlag) {
                                    _addHistoryItem(
                                      product,
                                      savedCode,
                                      isRegenerated: true,
                                    );
                                  } else if (wasScanned) {
                                    _addHistoryItem(
                                      product,
                                      savedCode,
                                      isScanned: true,
                                      isRescan: rescanFlag,
                                    );
                                  } else {
                                    _addHistoryItem(
                                      product,
                                      savedCode,
                                      isGenerated: true,
                                    );
                                  }
                                  _loadData();
                                }
                              }
                            }
                          : null,
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: const Text("SCAN"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: hasSku
                          ? () async {
                              final BuildContext parentCtx =
                                  _scaffoldKey.currentContext ?? context;
                              Navigator.pop(context);
                              final genResult = await Navigator.push(
                                parentCtx,
                                MaterialPageRoute(
                                  builder: (context) => BarcodeGeneratorScreen(
                                    product: product,
                                    sourceAction: sourceAction,
                                  ),
                                ),
                              );

                              if (genResult != null) {
                                if (genResult is Map &&
                                    genResult['saved'] == true) {
                                  final String savedCode =
                                      (genResult['barcode'] ??
                                              product['barcode'] ??
                                              'NEWLY GEN')
                                          .toString();
                                  final bool wasScanned =
                                      genResult['is_scanned'] == true;
                                  final bool rescanFlag =
                                      genResult['is_rescan'] == true;
                                  final bool regenFlag =
                                      genResult['is_regenerated'] == true;

                                  if (regenFlag) {
                                    _addHistoryItem(
                                      product,
                                      savedCode,
                                      isRegenerated: true,
                                    );
                                  } else if (wasScanned) {
                                    _addHistoryItem(
                                      product,
                                      savedCode,
                                      isScanned: true,
                                      isRescan: rescanFlag,
                                    );
                                  } else {
                                    _addHistoryItem(
                                      product,
                                      savedCode,
                                      isGenerated: true,
                                    );
                                  }
                                  _loadData();
                                } else if (genResult == true) {
                                  // Backwards compatibility: generator returned bool true
                                  _addHistoryItem(
                                    product,
                                    product['barcode'] ?? 'NEWLY GEN',
                                    isGenerated: true,
                                  );
                                  _loadData();
                                }
                              }
                            }
                          : null,
                      icon: const Icon(Icons.settings_overscan, size: 18),
                      label: const Text("GENERATE"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "CLOSE",
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isPrimary = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "$label:",
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
                color: isPrimary ? Colors.blue.shade900 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- DUPLICATE CHECK BY SKU ---

  Map<String, dynamic>? _checkBarcodeDuplicate(
    String newBarcode,
    String currentSku,
  ) {
    for (var product in allProducts) {
      final existingBarcode = (product['barcode'] ?? "").toString().trim();
      final productSku = (product['product_code'] ?? "").toString();
      if (existingBarcode == newBarcode && productSku != currentSku) {
        return product;
      }
    }
    return null;
  }

  void _showDuplicateError(String barcode, String otherProductName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.report_problem, color: Colors.red, size: 60),
            SizedBox(height: 10),
            Text(
              "BARCODE TAKEN",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "This barcode is already assigned to:",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              otherProductName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87,
              ),
            ),
            const Divider(height: 30),
            Text(
              "Code: $barcode",
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

  Future<bool> _showConfirmSaveDialog(String name, String newBarcode) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.help_outline, color: Colors.green),
                SizedBox(width: 10),
                Text("Confirm Save?", style: TextStyle(color: Colors.green)),
              ],
            ),
            content: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                children: [
                  const TextSpan(text: "Are you sure you want to assign\n"),
                  TextSpan(
                    text: newBarcode,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 20,
                    ),
                  ),
                  const TextSpan(text: "\n\nto\n"),
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: "?"),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "CANCEL",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("YES, SAVE IT"),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSuccessDialog(String name, String code) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            const Text(
              "SUCCESS!",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text("$name updated successfully.", textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "DONE",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addHistoryItem(
    Map<String, dynamic> product,
    String barcode, {
    bool isScanned = false,
    bool isRescan = false,
    bool isGenerated = false,
    bool isRegenerated = false,
  }) {
    setState(() {
      recentScans.insert(0, {
        'product_name': product['product_name'] ?? 'Unknown',
        'barcode': barcode,
        'time': DateTime.now(),
        'is_scanned': isScanned,
        'is_rescan': isRescan,
        'is_generated': isGenerated,
        'is_regenerated': isRegenerated,
        'original_data': product,
      });
    });
    _saveHistoryToDisk();
  }

  Future<void> updateProductBarcode(
    Map<String, dynamic> product,
    String newBarcode, {
    bool isRescan = false,
  }) async {
    final id = _getProductId(product);
    final pName = product['product_name'] ?? 'Unknown Product';
    final pSku = (product['product_code'] ?? "").toString();

    final duplicate = _checkBarcodeDuplicate(newBarcode, pSku);
    if (duplicate != null) {
      _showDuplicateError(
        newBarcode,
        duplicate['product_name'] ?? "Another Product",
      );
      return;
    }

    bool confirmed = await _showConfirmSaveDialog(pName, newBarcode);
    if (!confirmed) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.patch(
        Uri.parse('http://192.168.0.143:8056/items/products/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'barcode': newBarcode}),
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 200) {
        // Mark as scanned when updating via quick scan flow
        _addHistoryItem(
          product,
          newBarcode,
          isScanned: true,
          isRescan: isRescan,
        );
        _showSuccessDialog(pName, newBarcode);
        _fetchProducts();
      } else {
        _showSnackBar('❌ Update Failed');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Error: $e');
    }
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF4F7F9),
      endDrawer: _buildHistoryDrawer(),
      appBar: AppBar(
        title: const Text(
          'Inventory Master',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 28),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Open History',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(130),
          child: _buildFilterSection(),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _loadData, child: _buildProductList()),
      floatingActionButton: _showBackToTop ? _buildScrollToTopBtn() : null,
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      color: Colors.blue.shade900,
      child: Column(
        children: [
          TextField(
            onChanged: (val) {
              searchQuery = val;
              _applyFilters();
            },
            decoration: InputDecoration(
              hintText: "Search product name or ID...",
              prefixIcon: const Icon(Icons.search),
              fillColor: Colors.white,
              filled: true,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  hint: "Brand",
                  value: selectedBrandId,
                  items: brands,
                  idKey: 'brand_id',
                  nameKey: 'brand_name',
                  onChanged: (v) {
                    setState(() => selectedBrandId = v);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  hint: "Category",
                  value: selectedCategoryId,
                  items: categories,
                  idKey: 'category_id',
                  nameKey: 'category_name',
                  onChanged: (v) {
                    setState(() => selectedCategoryId = v);
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List items,
    required String idKey,
    required String nameKey,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          dropdownColor: Colors.blue.shade900,
          iconEnabledColor: Colors.white,
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: [
            DropdownMenuItem(value: null, child: Text("All $hint")),
            ...items.map(
              (item) => DropdownMenuItem(
                value: item[idKey].toString(),
                child: Text(item[nameKey].toString()),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildProductList() {
    if (filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const Text("No matches found."),
            TextButton(
              onPressed: () {
                setState(() {
                  searchQuery = "";
                  selectedBrandId = null;
                  selectedCategoryId = null;
                });
                _applyFilters();
              },
              child: const Text("Reset Filters"),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: filteredProducts.length,
      itemBuilder: (context, index) {
        final product = filteredProducts[index];
        final bool hasBarcode = (product['barcode'] ?? "")
            .toString()
            .trim()
            .isNotEmpty;
        final String pId = _getProductId(product).toString();

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: hasBarcode
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              child: Icon(
                hasBarcode ? Icons.inventory_2 : Icons.priority_high,
                color: hasBarcode ? Colors.green : Colors.red,
              ),
            ),
            title: Text(
              product['product_name'] ?? 'Unnamed',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasBarcode ? 'BC: ${product['barcode']}' : '⚠️ No Barcode',
                  style: TextStyle(
                    color: hasBarcode ? Colors.grey : Colors.red,
                    fontWeight: hasBarcode
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
                Text(
                  'ID: $pId',
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
              ],
            ),
            trailing: const Icon(Icons.info_outline, color: Colors.blue),
            onTap: () => _showProductDetails(product),
          ),
        );
      },
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue.shade900),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 50, color: Colors.white),
                  SizedBox(height: 8),
                  Text(
                    "Activity Log",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (recentScans.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${recentScans.length} Activities",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final p = await SharedPreferences.getInstance();
                      p.remove('barcode_history_key');
                      setState(() => recentScans.clear());
                    },
                    icon: const Icon(
                      Icons.delete_sweep,
                      color: Colors.red,
                      size: 20,
                    ),
                    label: const Text(
                      "Clear",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: recentScans.isEmpty
                ? const Center(child: Text("No history found"))
                : ListView.separated(
                    itemCount: recentScans.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = recentScans[i];
                      final DateTime time = item['time'];
                      final bool isScanned = item['is_scanned'] ?? false;
                      final bool isRescan = item['is_rescan'] ?? false;
                      final bool isGenerated = item['is_generated'] ?? false;
                      final bool isRegenerated =
                          item['is_regenerated'] ?? false;

                      String tag = "NEW";
                      Color color = Colors.grey;
                      IconData icon = Icons.add_to_photos;

                      if (isScanned && !isRescan) {
                        tag = "SCANNED";
                        color = Colors.green;
                        icon = Icons.qr_code;
                      } else if (isRescan) {
                        tag = "RESCAN";
                        color = Colors.orange;
                        icon = Icons.update;
                      } else if (isRegenerated) {
                        tag = "REGENERATED";
                        color = Colors.deepPurple;
                        icon = Icons.replay;
                      } else if (isGenerated) {
                        tag = "GENERATE";
                        color = Colors.purple;
                        icon = Icons.auto_awesome;
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.1),
                          child: Icon(icon, color: color, size: 18),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item['product_name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Code: ${item['barcode']}",
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              DateFormat('MMM dd • hh:mm a').format(time),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          // Tap history to open details popup
                          Navigator.pop(context); // Close drawer
                          _showProductDetails(
                            item['original_data'],
                            history: item,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollToTopBtn() {
    return FloatingActionButton(
      onPressed: () => _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.ease,
      ),
      backgroundColor: Colors.blue.shade900,
      mini: true,
      child: const Icon(Icons.arrow_upward, color: Colors.white),
    );
  }

  dynamic _getProductId(Map<String, dynamic> p) {
    for (var k in ['product_id', 'id', 'itemId', 'item_id']) {
      if (p[k] != null) return p[k];
    }
    return "N/A";
  }

  void _showSnackBar(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
  );
}
