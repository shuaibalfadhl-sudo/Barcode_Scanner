import 'dart:async'; 
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'scanner.dart';
import 'barcode_generator.dart';
import 'print.dart';

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
  List units = []; 
  List<Map<String, dynamic>> recentScans = [];
  String? selectedSku;
  List<String> skuList = [];

  // State Management
  bool isLoading = true;
  bool _isOffline = false; 
  bool _isSyncing = false; 
  String searchQuery = "";
  String? selectedBrandId;
  String? selectedCategoryId;
  String? selectedUnitId; 

  Timer? _debounce; 

  // Scroll Management
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadData(isInitialLoad: true); 
    _loadStoredHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _debounce?.cancel(); 
    super.dispose();
  }

  // --- SCROLL & HISTORY PERSISTENCE ---

  void _onScroll() {
    setState(() {
      _showBackToTop = _scrollController.offset > 300;
    });
  }

  String _getUnitName(dynamic unitId) {
    if (unitId == null || units.isEmpty) return "N/A";
    final unit = units.firstWhere(
      (u) => u['unit_id'].toString() == unitId.toString(),
      orElse: () => null,
    );
    return unit != null ? unit['unit_name'].toString() : "N/A";
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
                'is_synced': item['is_synced'] ?? true, 
                'time': DateTime.tryParse(item['time'] ?? '') ?? DateTime.now(),
                'original_data': item['original_data'],
              },
            )
            .toList();
      });
    }
  }

  // --- API & FILTERING ---

  Future<void> _loadData({bool isInitialLoad = false}) async {
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchProducts(isInitialLoad: isInitialLoad), 
        _fetchBrands(),
        _fetchCategories(),
        _fetchUnits(),
      ]);
    } catch (e) {
      _showSnackBar('Init Error: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchUnits() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await http.get(Uri.parse('http://192.168.0.143:8091/items/units?limit=-1')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body)['data'];
        await prefs.setString('cached_units', json.encode(data)); 
        if (mounted) setState(() => units = data);
      }
    } catch (_) {
      final cached = prefs.getString('cached_units');
      if (cached != null && mounted) setState(() => units = json.decode(cached));
    }
  }

  Future<void> _fetchProducts({bool isInitialLoad = false}) async {
    setState(() => isLoading = true); 
    final prefs = await SharedPreferences.getInstance();

    try {
      String url = 'http://192.168.0.143:8091/items/products?limit=-1';
      
      if (searchQuery.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(searchQuery)}';
      }

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        _isOffline = false; 
        List data = json.decode(response.body)['data'];
        
        if (searchQuery.isEmpty) {
          await prefs.setString('cached_products', json.encode(data));
        }

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
      }
    } catch (e) {
      debugPrint("Error fetching products, falling back to cache: $e");
      _isOffline = true; 
      
      final cached = prefs.getString('cached_products');
      if (cached != null) {
        List data = json.decode(cached);
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
      } else {
        allProducts = []; 
      }

      if (isInitialLoad && allProducts.isNotEmpty && mounted) {
        _showSnackBar('Offline Mode: Showing cached products');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _applyFilters();
      }
    }
  }

  Future<void> _fetchBrands() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await http.get(Uri.parse('http://192.168.0.143:8091/items/brand?limit=-1')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body)['data'];
        await prefs.setString('cached_brands', json.encode(data)); 
        if (mounted) setState(() => brands = data);
      }
    } catch (_) {
      final cached = prefs.getString('cached_brands');
      if (cached != null && mounted) setState(() => brands = json.decode(cached));
    }
  }

  Future<void> _fetchCategories() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await http.get(Uri.parse('http://192.168.0.143:8091/items/categories?limit=-1')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body)['data'];
        await prefs.setString('cached_categories', json.encode(data)); 
        if (mounted) setState(() => categories = data);
      }
    } catch (_) {
      final cached = prefs.getString('cached_categories');
      if (cached != null && mounted) setState(() => categories = json.decode(cached));
    }
  }

  // <--- CHANGE: Helper to FORCE UPDATE the local offline cache immediately when a barcode is created
  Future<void> _updateLocalProductCache(String productId, String newBarcode) async {
    // 1. Update the list actively in memory
    for (var p in allProducts) {
      if (_getProductId(p).toString() == productId) {
        p['barcode'] = newBarcode;
        break;
      }
    }
    
    // 2. Overwrite the saved offline cache so it remembers the change
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_products', json.encode(allProducts));
    
    // 3. Re-filter the UI to show the new barcode immediately
    if (mounted) {
      _applyFilters();
    }
  }

  void _applyFilters() {
    setState(() {
      filteredProducts = allProducts.where((p) {
        final query = searchQuery.toLowerCase();
        final name = (p['product_name'] ?? "").toString().toLowerCase();
        final pId = _getProductId(p).toString().toLowerCase();
        final skuValue = (p['product_code'] ?? "").toString();

        final matchesSearch = name.contains(query) || pId.contains(query) || skuValue.toLowerCase().contains(query);

        final String pBrand = (p['product_brand'] ?? "").toString();
        final bool matchesBrand = selectedBrandId == null || pBrand == selectedBrandId;
        
        final String pCategory = (p['product_category'] ?? "").toString();
        final bool matchesCategory = selectedCategoryId == null || pCategory == selectedCategoryId;

        final String pUnit = (p['unit_of_measurement'] ?? "").toString();
        final bool matchesUnit = selectedUnitId == null || pUnit == selectedUnitId;

        bool matchesSku = true;
        if (selectedSku == "With SKU") {
          matchesSku = skuValue.trim().isNotEmpty && skuValue != "null";
        } else if (selectedSku == "No SKU") {
          matchesSku = skuValue.trim().isEmpty || skuValue == "null";
        }

        return matchesSearch && matchesBrand && matchesCategory && matchesSku && matchesUnit; 
      }).toList();
    });
  }

  Future<void> _syncOfflineData() async {
    setState(() => _isSyncing = true);
    int syncedCount = 0;
    int failCount = 0;

    for (var item in recentScans) {
      if (item['is_synced'] == false) {
        try {
          final productId = _getProductId(item['original_data']);
          final barcode = item['barcode'];
          
          final response = await http.patch(
            Uri.parse('http://192.168.0.143:8091/items/products/$productId'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'barcode': barcode}),
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            item['is_synced'] = true; // Mark as synced!
            syncedCount++;
          } else {
            failCount++;
          }
        } catch (e) {
          failCount++;
        }
      }
    }

    await _saveHistoryToDisk();
    
    // <--- CHANGE: Force a Full Refresh. We temporarily clear the search query so the app 
    // downloads the ENTIRE database of products from the server to refresh the local cache perfectly.
    String tempSearch = searchQuery;
    searchQuery = ""; 
    await _fetchProducts(); 
    searchQuery = tempSearch;
    _applyFilters();
    
    setState(() {
      _isSyncing = false;
      _isOffline = failCount > 0; // If any failed, we assume network is still bad
    });

    if (syncedCount > 0) {
      _showSnackBar('✅ Successfully synced $syncedCount items!');
    }
    if (failCount > 0) {
      _showSnackBar('❌ Failed to sync $failCount items. Still offline?');
    }
  }

  // --- PRODUCT INFO DIALOG ---

  void _showProductDetails(
    Map<String, dynamic> product, {
    Map<String, dynamic>? history,
  }) {
    String getValue(String key) {
      final val = product[key];
      if (val == null || val.toString().trim().isEmpty || val.toString() == "null") return "N/A";
      return val.toString();
    }

    String getBarcodeType(dynamic id) {
      if (id.toString() == "1") return "EAN-13";
      if (id.toString() == "2") return "Code 128";
      return "N/A";
    }

    String getWeightUnit(dynamic id) {
      final unitsMap = {"1": "G", "2": "KG", "3": "LB", "4": "OZ"};
      return unitsMap[id.toString()] ?? "";
    }

    String getCbmUnit(dynamic id) {
      final unitsMap = {"1": "MM", "2": "CM", "3": "M", "4": "IN", "5": "FT"};
      return unitsMap[id.toString()] ?? "";
    }

    final String sku = getValue('product_code');
    final String prodId = _getProductId(product).toString();
    final bool hasSku = sku != "N/A";
    final String weightUnit = getWeightUnit(product['weight_unit_id']);
    final String cbmUnit = getCbmUnit(product['cbm_unit_id']);
    final String unitName = _getUnitName(product['unit_of_measurement']); 

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
              _detailRow("Bundle Type", unitName), 
              _detailRow("Barcode", getValue('barcode')),
              _detailRow("BC Type", getBarcodeType(product['barcode_type_id'])),
              const Divider(),
              _detailRow("Weight", "${getValue('weight')} $weightUnit"),
              const SizedBox(height: 8),
              const Text(
                "Dimensions (CBM)",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              _detailRow("Length", "${getValue('cbm_length')} $cbmUnit"),
              _detailRow("Width", "${getValue('cbm_width')} $cbmUnit"),
              _detailRow("Height", "${getValue('cbm_height')} $cbmUnit"),
              if (!hasSku)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    "⚠️ Actions disabled: SKU is missing",
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // --- SCAN BUTTON ---
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: hasSku ? () async {
                        final BuildContext parentCtx = _scaffoldKey.currentContext ?? context;
                        final bool alreadyHasBarcode = (product['barcode'] ?? "").toString().trim().isNotEmpty;
                        final String effectiveAction = alreadyHasBarcode ? 'rescan' : 'scan';

                        Navigator.pop(context); // Close Info Dialog
                        
                        final result = await Navigator.push(
                          parentCtx,
                          MaterialPageRoute(builder: (_) => CameraScannerPage(product: product)),
                        );

                        if (result != null && result['value'] != null) {
                          final genResult = await Navigator.push(
                            parentCtx,
                            MaterialPageRoute(
                              builder: (context) => BarcodeGeneratorScreen(
                                product: product,
                                scannedBarcode: result['value'],
                                sourceAction: effectiveAction,
                              ),
                            ),
                          );

                          if (genResult != null && genResult['saved'] == true) {
                            final String savedCode = genResult['barcode'].toString();
                            
                            final bool isOfflineSave = _isOffline || (genResult['is_offline'] == true);

                            _showSuccessDialog(product['product_name'] ?? "Product", savedCode);
                            
                            _addHistoryItem(
                              product,
                              savedCode,
                              isScanned: true,
                              isRescan: effectiveAction == 'rescan',
                              isSynced: !isOfflineSave, 
                            );
                            
                            // <--- CHANGE: First, aggressively update the local memory so it updates INSTANTLY 
                            await _updateLocalProductCache(prodId, savedCode);
                            // Then attempt normal fetch to keep server in sync if we are online
                            _fetchProducts(); 
                          }
                        }
                      } : null,
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: const Text("SCAN"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // --- GENERATE BUTTON ---
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: hasSku ? () async {
                        final BuildContext parentCtx = _scaffoldKey.currentContext ?? context;
                        final bool alreadyHasBarcode = (product['barcode'] ?? "").toString().trim().isNotEmpty;
                        final String effectiveAction = alreadyHasBarcode ? 'regenerate' : 'generate';

                        Navigator.pop(context);

                        final genResult = await Navigator.push(
                          parentCtx,
                          MaterialPageRoute(
                            builder: (context) => BarcodeGeneratorScreen(
                              product: product,
                              sourceAction: effectiveAction,
                            ),
                          ),
                        );

                        if (genResult != null && genResult['saved'] == true) {
                          final String savedCode = genResult['barcode'].toString();
                          
                          final bool isOfflineSave = _isOffline || (genResult['is_offline'] == true);

                          _showSuccessDialog(product['product_name'] ?? "Product", savedCode);

                          _addHistoryItem(
                            product,
                            savedCode,
                            isGenerated: effectiveAction == 'generate',
                            isRegenerated: effectiveAction == 'regenerate',
                            isSynced: !isOfflineSave, 
                          );
                          
                          // <--- CHANGE: First, aggressively update the local memory so it updates INSTANTLY
                          await _updateLocalProductCache(prodId, savedCode);
                          // Then attempt normal fetch to keep server in sync if we are online
                          _fetchProducts(); 
                        }
                      } : null,
                      icon: const Icon(Icons.settings_overscan, size: 18),
                      label: const Text("GENERATE"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CLOSE", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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

  void _showSuccessDialog(String name, String code) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 60),
          ),
          const SizedBox(height: 20),
          const Text(
            "BARCODE SAVED",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade900,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text("CONTINUE", style: TextStyle(fontWeight: FontWeight.bold)),
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
    bool isSynced = true, 
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
        'is_synced': isSynced, 
        'original_data': product,
      });
    });
    _saveHistoryToDisk();
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
        'Product Barcoding',
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
        preferredSize: const Size.fromHeight(185), 
        child: _buildFilterSection(),
      ),
    ),
    body: isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () async {
              _isOffline = false; 
              await _loadData();
            }, 
            child: _buildProductList()
          ),
    
    floatingActionButton: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_showBackToTop) ...[
          _buildScrollToTopBtn(),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          heroTag: "batch_print_btn",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PrintScreen(allProducts: allProducts),
              ),
            );
          },
          backgroundColor: Colors.green.shade700,
          child: const Icon(Icons.print, color: Colors.white),
        ),
      ],
    ),
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
              if (_isOffline) {
                _applyFilters();
              } else {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  _fetchProducts(); 
                });
              }
            },
            decoration: InputDecoration(
              hintText: "Search name, ID, or SKU...",
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSimpleDropdown(
                  hint: "SKU",
                  value: selectedSku,
                  items: ["With SKU", "No SKU"],
                  onChanged: (v) {
                    setState(() => selectedSku = v);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  hint: "Unit",
                  value: selectedUnitId,
                  items: units,
                  idKey: 'unit_id',
                  nameKey: 'unit_name',
                  onChanged: (v) {
                    setState(() => selectedUnitId = v);
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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

Widget _buildSimpleDropdown({
  required String hint,
  required String? value,
  required List<String> items,
  required Function(String?) onChanged,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        hint: Text(hint, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        dropdownColor: Colors.blue.shade900,
        iconEnabledColor: Colors.white,
        isExpanded: true,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        items: [
          DropdownMenuItem(value: null, child: Text("All $hint")),
          ...items.map((s) => DropdownMenuItem(value: s, child: Text(s))),
        ],
        onChanged: onChanged,
      ),
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
    String displayValue = "All $hint";
    if (value != null) {
      final selectedItem = items.firstWhere(
        (item) => item[idKey].toString() == value,
        orElse: () => null,
      );
      if (selectedItem != null) {
        displayValue = selectedItem[nameKey].toString();
      }
    }

    return InkWell(
      onTap: () => _showFilterModal(
        context: context,
        title: hint,
        items: items,
        idKey: idKey,
        nameKey: nameKey,
        currentValue: value,
        onChanged: onChanged,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                displayValue,
                style: TextStyle(
                  color: value == null ? Colors.white70 : Colors.white, 
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  void _showFilterModal({
    required BuildContext context,
    required String title,
    required List items,
    required String idKey,
    required String nameKey,
    required String? currentValue,
    required Function(String?) onChanged,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        String modalSearchQuery = "";
        
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final filteredList = items.where((item) {
              return item[nameKey]
                  .toString()
                  .toLowerCase()
                  .contains(modalSearchQuery.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7, 
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40, 
                      height: 5, 
                      decoration: BoxDecoration(
                        color: Colors.grey[300], 
                        borderRadius: BorderRadius.circular(10)
                      )
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "Select $title", 
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        onChanged: (val) {
                          setModalState(() {
                            modalSearchQuery = val;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: "Search $title...",
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            title: Text(
                              "All $title", 
                              style: TextStyle(
                                fontWeight: currentValue == null ? FontWeight.bold : FontWeight.normal,
                                color: currentValue == null ? Colors.blue.shade900 : Colors.black87
                              )
                            ),
                            trailing: currentValue == null ? Icon(Icons.check_circle, color: Colors.blue.shade900) : null,
                            onTap: () {
                              onChanged(null);
                              Navigator.pop(context);
                            },
                          ),
                          const Divider(height: 1),
                          ...filteredList.map((item) {
                            final bool isSelected = currentValue == item[idKey].toString();
                            return Column(
                              children: [
                                ListTile(
                                  title: Text(
                                    item[nameKey].toString(), 
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? Colors.blue.shade900 : Colors.black87
                                    )
                                  ),
                                  trailing: isSelected ? Icon(Icons.check_circle, color: Colors.blue.shade900) : null,
                                  onTap: () {
                                    onChanged(item[idKey].toString());
                                    Navigator.pop(context);
                                  },
                                ),
                                const Divider(height: 1),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
                  selectedUnitId = null; 
                  selectedSku = null;
                });
                if (_isOffline) {
                  _applyFilters();
                } else {
                  _fetchProducts(); 
                }
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
        final String unitName = _getUnitName(product['unit_of_measurement']); 

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
                  "Unit: $unitName",
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                ),
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
    int unsyncedCount = recentScans.where((item) => item['is_synced'] == false).length;

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
          
          if (unsyncedCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isSyncing ? null : _syncOfflineData,
                icon: _isSyncing 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Icon(Icons.sync),
                label: Text(_isSyncing ? "Syncing..." : "Sync $unsyncedCount Offline Items"),
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
                      final bool isRegenerated = item['is_regenerated'] ?? false;
                      final bool isSynced = item['is_synced'] ?? true; 

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
                            if (!isSynced)
                              Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  "UNSYNCED",
                                  style: TextStyle(
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
                          
                          Navigator.pop(context); // Close drawer

                          final originalData =
                              item['original_data'] as Map<String, dynamic>;
                          final productId = _getProductId(originalData);

                          final freshProduct = allProducts.firstWhere(
                            (p) => _getProductId(p) == productId,
                            orElse: () => originalData,
                          );

                          _showProductDetails(freshProduct, history: item);
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