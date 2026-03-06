import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; 
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'barcode_generator.dart';
import '../widgets/drawer.dart';
import '/bundle/widgets/widget_search.dart';
import '/bundle/widgets/widget_history.dart'; // NEW IMPORT
import '/bundle/print.dart';
import 'scanner.dart';
import '../utils/user_helper.dart';

class BundleScreen extends StatefulWidget {
  const BundleScreen({Key? key}) : super(key: key);

  @override
  State<BundleScreen> createState() => _BundleScreenState();
}

class _BundleScreenState extends State<BundleScreen> {
  List<dynamic> _bundles = [];
  List<dynamic> _filteredBundles = [];

  List<dynamic> _bundleTypes = [];
  List<dynamic> _bundleItems = [];
  List<dynamic> _barcodeTypes = [];
  List<dynamic> _weightUnits = [];
  List<dynamic> _cbmUnits = [];
  List<dynamic> _users = []; // --- ALL USERS FROM API ---

  List<Map<String, dynamic>> _historyLogs = [];

  // --- LOGGED-IN USER DATA ---
  int? _currentUserId;
  String? _currentUserName;

  bool _isLoading = true;
  bool _isSyncing = false; // --- TRACKS SYNC STATE ---
  String? _errorMessage;
  String _currentSearchQuery = ''; // Tracks search across background syncs

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadHistoryFromCache();
    _initializeOfflineFirstData();
  }

  // --- LOAD CURRENT USER DATA ---
  Future<void> _loadCurrentUser() async {
    final userId = await UserHelper.getLoggedInUserId();
    final userName = await UserHelper.getLoggedInUserName();
    setState(() {
      _currentUserId = userId;
      _currentUserName = userName;
    });
  }

  // --- OFFLINE FIRST INIT ---
  Future<void> _initializeOfflineFirstData() async {
    await _loadCachedData(); // 1. Load instantly from cache
    _fetchAllData();         // 2. Fetch fresh data from API in background
  }

  // --- LOAD FROM CACHE ---
  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final bundlesStr = prefs.getString('cached_bundles');
    final typesStr = prefs.getString('cached_bundle_types');
    final itemsStr = prefs.getString('cached_bundle_items');
    final barcodeTypesStr = prefs.getString('cached_barcode_types');
    final weightUnitsStr = prefs.getString('cached_weight_units');
    final cbmUnitsStr = prefs.getString('cached_cbm_units');
    final usersStr = prefs.getString('cached_users');

    if (bundlesStr != null) {
      setState(() {
        _bundles = json.decode(bundlesStr);
        _filteredBundles = _bundles;
        
        if (typesStr != null) _bundleTypes = json.decode(typesStr);
        if (itemsStr != null) _bundleItems = json.decode(itemsStr);
        if (barcodeTypesStr != null) _barcodeTypes = json.decode(barcodeTypesStr);
        if (weightUnitsStr != null) _weightUnits = json.decode(weightUnitsStr);
        if (cbmUnitsStr != null) _cbmUnits = json.decode(cbmUnitsStr);
        if (usersStr != null) _users = json.decode(usersStr);

        _isLoading = false; // Turn off loading immediately since we have local data
      });
      debugPrint("✅ Loaded bundle data from local cache.");
    }
  }

  void _runSearch(String query) {
    setState(() {
      _currentSearchQuery = query;
      if (query.isEmpty) {
        _filteredBundles = _bundles;
      } else {
        _filteredBundles = _bundles.where((bundle) {
          final name = (bundle['bundle_name'] ?? '').toString().toLowerCase();
          final sku = (bundle['bundle_sku'] ?? '').toString().toLowerCase();
          final id = (bundle['id'] ?? '').toString().toLowerCase();
          final searchLower = query.toLowerCase();

          return name.contains(searchLower) || sku.contains(searchLower) || id.contains(searchLower);
        }).toList();
      }
    });
  }

  Future<void> _loadHistoryFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cachedData = prefs.getString('bundle_history_logs');
    if (cachedData != null) {
      setState(() {
        _historyLogs = List<Map<String, dynamic>>.from(json.decode(cachedData));
        // --- SORT BY TIMESTAMP (LATEST FIRST) ---
        _historyLogs.sort((a, b) {
          final dynamic rawTimeA = a['time'] ?? a['timestamp'];
          final dynamic rawTimeB = b['time'] ?? b['timestamp'];

          final DateTime timeA = rawTimeA is String ? (DateTime.tryParse(rawTimeA) ?? DateTime.now()) : (rawTimeA ?? DateTime.now());
          final DateTime timeB = rawTimeB is String ? (DateTime.tryParse(rawTimeB) ?? DateTime.now()) : (rawTimeB ?? DateTime.now());

          return timeB.compareTo(timeA); // Descending order (latest first)
        });
      });
    }
  }

  Future<void> _printReport() async {
    if (_filteredBundles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data available to print.")));
      return;
    }

    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) => [
            pw.Header(level: 0, child: pw.Text("Bundle Inventory Report")),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              context: context,
              data: <List<String>>[
                <String>['ID', 'Bundle Name', 'SKU', 'Status'],
                ..._filteredBundles.map((item) => [item['id'].toString(), item['bundle_name']?.toString() ?? 'N/A', item['bundle_sku']?.toString() ?? 'N/A', item['status']?.toString() ?? 'Draft']),
              ],
            ),
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'bundle_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      debugPrint("🔴 Print Error: $e");
    }
  }

  Future<void> _saveHistoryToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bundle_history_logs', json.encode(_historyLogs));
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bundle_history_logs');
    setState(() => _historyLogs.clear());
  }

  // --- SYNC OFFLINE ITEMS LOGIC ---
  Future<void> _syncOfflineItems() async {
    setState(() {
      _isSyncing = true;
    });

    int successCount = 0;
    int failCount = 0;

    // Get all unsynced items
    final unsyncedLogs = _historyLogs.where((log) => log['is_synced'] == false).toList();

    for (var log in unsyncedLogs) {
      try {
        final bundleId = log['bundle_id'];
        final barcode = log['barcode'] ?? log['new_barcode'];

        final updateData = {
          'barcode_value': barcode,
          'updated_by': _currentUserId,
          'updated_at': DateTime.now().toIso8601String()
        };

        final response = await http.patch(
          Uri.parse('http://192.168.0.143:8056/items/product_bundles/$bundleId'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updateData),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 || response.statusCode == 204) {
          // Success: Mark this specific log as synced
          setState(() {
            log['is_synced'] = true;
          });
          successCount++;
          debugPrint('✅ Successfully synced offline bundle $bundleId');
        } else {
          failCount++;
          debugPrint('⚠️ Failed to sync offline bundle $bundleId: ${response.statusCode}');
        }
      } catch (e) {
        failCount++;
        debugPrint('⚠️ Error syncing offline bundle: $e');
      }
    }

    // Save the updated statuses to cache
    await _saveHistoryToCache();

    // Fetch fresh data if at least one item was successfully pushed to API
    if (successCount > 0) {
      await _fetchAllData();
    }

    setState(() {
      _isSyncing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failCount == 0 
            ? "Successfully synced $successCount items!" 
            : "Synced $successCount items. $failCount failed. Check connection."),
          backgroundColor: failCount == 0 ? Colors.green.shade700 : Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _fetchAllData() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('http://192.168.0.143:8056/items/product_bundles')),
        http.get(Uri.parse('http://192.168.0.143:8056/items/product_bundle_types')),
        http.get(Uri.parse('http://192.168.0.143:8056/items/product_bundle_items')),
        http.get(Uri.parse('http://192.168.0.143:8056/items/barcode_type')),
        http.get(Uri.parse('http://192.168.0.143:8056/items/weight_unit')),
        http.get(Uri.parse('http://192.168.0.143:8056/items/cbm_unit')),
        http.get(Uri.parse('http://192.168.0.143:8091/items/user')), // --- FETCH USERS ---
      ]).timeout(const Duration(seconds: 15));

      if (responses.every((r) => r.statusCode == 200)) {
        final prefs = await SharedPreferences.getInstance();

        // Extract data
        final fetchedBundles = json.decode(responses[0].body)['data'] ?? [];
        final fetchedTypes = json.decode(responses[1].body)['data'] ?? [];
        final fetchedItems = json.decode(responses[2].body)['data'] ?? [];
        final fetchedBarcodeTypes = json.decode(responses[3].body)['data'] ?? [];
        final fetchedWeightUnits = json.decode(responses[4].body)['data'] ?? [];
        final fetchedCbmUnits = json.decode(responses[5].body)['data'] ?? [];
        final fetchedUsers = json.decode(responses[6].body)['data'] ?? [];

        // Save fresh data to cache
        await prefs.setString('cached_bundles', json.encode(fetchedBundles));
        await prefs.setString('cached_bundle_types', json.encode(fetchedTypes));
        await prefs.setString('cached_bundle_items', json.encode(fetchedItems));
        await prefs.setString('cached_barcode_types', json.encode(fetchedBarcodeTypes));
        await prefs.setString('cached_weight_units', json.encode(fetchedWeightUnits));
        await prefs.setString('cached_cbm_units', json.encode(fetchedCbmUnits));
        await prefs.setString('cached_users', json.encode(fetchedUsers));

        setState(() {
          _bundles = fetchedBundles;
          _bundleTypes = fetchedTypes;
          _bundleItems = fetchedItems;
          _barcodeTypes = fetchedBarcodeTypes;
          _weightUnits = fetchedWeightUnits;
          _cbmUnits = fetchedCbmUnits;
          _users = fetchedUsers;
          
          _isLoading = false;
          _errorMessage = null;

          // Re-apply search so the list doesnt reset unexpectedly if the user was typing
          _runSearch(_currentSearchQuery);
        });
        debugPrint("✅ Fetched and cached fresh API data.");
      } else {
        // Only show error if we have NO cached data to fall back on
        if (_bundles.isEmpty) {
          setState(() {
            _errorMessage = "Server error fetching bundle data.";
            _isLoading = false;
          });
        } else {
          debugPrint("⚠️ API fetch failed, but continuing with cached data.");
        }
      }
    } catch (e) {
      // Offline or Timeout: Only disrupt the user if cache is completely empty
      if (_bundles.isEmpty) {
        setState(() {
          _errorMessage = "Failed to load data. Check network connection.\n$e";
          _isLoading = false;
        });
      } else {
        debugPrint("⚠️ Network offline. Continuing with cached data. Error: $e");
        setState(() {
          _isLoading = false; // ensure loading spinner stops
        });
      }
    }
  }

  String _getTypeName(dynamic typeId) {
    if (typeId == null || typeId.toString() == "null") return 'Pieces';
    try {
      for (var type in _bundleTypes) {
        if (type['id'].toString() == typeId.toString()) {
          return type['name']?.toString() ?? 'Unknown Type';
        }
      }
      return 'Unknown Type';
    } catch (e) {
      return 'Pieces';
    }
  }

  String _getBarcodeTypeName(dynamic typeId) {
    if (typeId == null || typeId.toString() == "null" || typeId.toString().isEmpty) return 'N/A';
    try {
      for (var type in _barcodeTypes) {
        if (type['id'].toString() == typeId.toString()) {
          return type['name']?.toString() ?? 'Unnamed Type';
        }
      }
      return 'Unknown ID: $typeId';
    } catch (e) {
      return 'N/A';
    }
  }

  String _getWeightUnitCode(dynamic unitId) {
    if (unitId == null || unitId.toString() == "null" || unitId.toString().isEmpty) return '';
    try {
      for (var unit in _weightUnits) {
        if (unit['id'].toString() == unitId.toString()) {
          return unit['code']?.toString() ?? '';
        }
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  String _getCbmUnitCode(dynamic unitId) {
    if (unitId == null || unitId.toString() == "null" || unitId.toString().isEmpty) return '';
    try {
      for (var unit in _cbmUnits) {
        if (unit['id'].toString() == unitId.toString()) {
          return unit['code']?.toString() ?? '';
        }
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  void _showBundleDetails(Map<String, dynamic> bundle) {
    // Determine if the product is in Draft state
    final bool isDraft = (bundle['status'] ?? 'Draft').toString().toLowerCase() == 'draft';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF4F4F9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        String weightValue = bundle['weight']?.toString() ?? 'N/A';
        String weightUnit = _getWeightUnitCode(bundle['weight_unit_id']);
        String displayWeight = weightValue == 'N/A' ? 'N/A' : '$weightValue $weightUnit'.trim();

        String cbmUnit = _getCbmUnitCode(bundle['cbm_unit_id']);
        String lengthValue = bundle['cbm_length']?.toString() ?? 'N/A';
        String widthValue = bundle['cbm_width']?.toString() ?? 'N/A';
        String heightValue = bundle['cbm_height']?.toString() ?? 'N/A';

        String displayLength = lengthValue == 'N/A' ? 'N/A' : '$lengthValue $cbmUnit'.trim();
        String displayWidth = widthValue == 'N/A' ? 'N/A' : '$widthValue $cbmUnit'.trim();
        String displayHeight = heightValue == 'N/A' ? 'N/A' : '$heightValue $cbmUnit'.trim();

        // WRAPPED IN SingleChildScrollView TO PREVENT VERTICAL OVERFLOW
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0, bottom: MediaQuery.of(context).padding.bottom + 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bundle['bundle_name'] ?? 'Unknown Bundle',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF2C2C38), height: 1.2),
                ),
                const SizedBox(height: 20),

                _buildDetailRow('ID:', bundle['id']?.toString() ?? 'N/A', valueColor: Colors.green.shade700, isBold: true),
                _buildDetailRow('SKU:', bundle['bundle_sku'] ?? 'N/A'),
                _buildDetailRow('Bundle Type:', _getTypeName(bundle['bundle_type_id'])),
                _buildDetailRow('Barcode:', bundle['barcode_value'] ?? 'N/A'),
                _buildDetailRow('BC Type:', _getBarcodeTypeName(bundle['barcode_type_id'])),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(color: Colors.black12, thickness: 1),
                ),

                // --- UPDATED BY INFO ---
                if (bundle['updated_by'] != null) _buildDetailRow('Updated By:', _getUserNameById(bundle['updated_by']), valueColor: Colors.deepOrange.shade600),
                if (bundle['updated_at'] != null) _buildDetailRow('Updated At:', _formatDate(bundle['updated_at']), valueColor: Colors.grey.shade700),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(color: Colors.black12, thickness: 1),
                ),

                _buildDetailRow('Weight:', displayWeight),
                const SizedBox(height: 8),

                const Text(
                  'Dimensions (CBM)',
                  style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                _buildDetailRow('Length:', displayLength),
                _buildDetailRow('Width:', displayWidth),
                _buildDetailRow('Height:', displayHeight),

                const SizedBox(height: 24),

                // --- DRAFT WARNING BANNER ---
                if (isDraft)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Scanning and generating barcodes are disabled for Draft bundles.',
                            style: TextStyle(color: Colors.orange.shade800, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        // Disabled if draft
                        onPressed: isDraft ? null : () async {
                          Navigator.pop(context); // Close the bottom sheet first

                          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => CameraScannerPage(product: bundle)));

                          // scanner.dart now handles the complete scan-to-generator flow
                          // and returns the final result with all flags set
                          if (result != null && result is Map && result['saved'] == true) {
                            bool isOffline = result['is_offline'] == true;
                            final String action = result['action'] ?? 'scanned';

                            // Check if bundle already has a barcode
                            bool hasExistingBarcode = (bundle['barcode_value'] ?? "").toString().trim().isNotEmpty;

                            setState(() {
                              // --- TYPE-SAFE LOCAL UI UPDATE ---
                              int index = _bundles.indexWhere((b) => b['id'].toString() == bundle['id'].toString());
                              if (index != -1) {
                                _bundles[index]['barcode_value'] = result['barcode'];
                                int filterIndex = _filteredBundles.indexWhere((b) => b['id'].toString() == bundle['id'].toString());
                                if (filterIndex != -1) {
                                  _filteredBundles[filterIndex]['barcode_value'] = result['barcode'];
                                }
                              }

                              // --- BULLETPROOF HISTORY LOG INSERTION WITH STATUS ---
                              _historyLogs.insert(0, {
                                'bundle_id': bundle['id'],
                                'bundle_name': bundle['bundle_name'],
                                'name': bundle['bundle_name'],
                                'sku': bundle['bundle_sku'],
                                'new_barcode': result['barcode'],
                                'barcode': result['barcode'],
                                'timestamp': DateTime.now().toIso8601String(),
                                'action': action,
                                'is_scanned': action == 'scanned' || action == 'scan',
                                'is_rescan': action == 'rescan',
                                'is_synced': !isOffline,
                                'updated_by': _currentUserId,
                                'updated_by_name': _currentUserName ?? 'Unknown User',
                              });
                            });

                            _saveHistoryToCache();
                            
                            // Try to fetch data in background to stay synced if online
                            _fetchAllData();

                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(isOffline ? "Saved offline. Please sync later." : "Scanned barcode saved successfully!"),
                                  backgroundColor: isOffline ? Colors.orange.shade800 : Colors.green.shade700,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          }
                        },
                        icon: Icon(Icons.qr_code_scanner, color: isDraft ? Colors.grey.shade600 : Colors.white, size: 20),
                        // WRAPPED IN FITTEDBOX TO PREVENT HORIZONTAL OVERFLOW ON SMALL SCREENS
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'SCAN',
                            style: TextStyle(color: isDraft ? Colors.grey.shade600 : Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDraft ? Colors.grey.shade300 : Colors.green.shade700,
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        // Disabled if draft
                        onPressed: isDraft ? null : () async {
                          Navigator.pop(context); // Close the bottom sheet first

                          final String effectiveAction = (bundle['barcode_value'] ?? "").toString().trim().isNotEmpty ? 'regenerate' : 'generate';

                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BarcodeGeneratorScreen(product: bundle, sourceAction: effectiveAction),
                            ),
                          );

                          if (result != null && result['saved'] == true) {
                            bool isOffline = result['is_offline'] == true;

                            // Check if bundle already has a barcode
                            bool hasExistingBarcode = (bundle['barcode_value'] ?? "").toString().trim().isNotEmpty;

                            setState(() {
                              // --- TYPE-SAFE LOCAL UI UPDATE ---
                              int index = _bundles.indexWhere((b) => b['id'].toString() == bundle['id'].toString());
                              if (index != -1) {
                                _bundles[index]['barcode_value'] = result['barcode'];
                                int filterIndex = _filteredBundles.indexWhere((b) => b['id'].toString() == bundle['id'].toString());
                                if (filterIndex != -1) {
                                  _filteredBundles[filterIndex]['barcode_value'] = result['barcode'];
                                }
                              }

                              _historyLogs.insert(0, {
                                'bundle_id': bundle['id'],
                                'name': bundle['bundle_name'],
                                'sku': bundle['bundle_sku'],
                                'new_barcode': result['barcode'],
                                'timestamp': DateTime.now().toIso8601String(),
                                'action': effectiveAction == 'regenerate' ? 'regenerated' : 'generate',
                                'is_generated': true,
                                'is_synced': !isOffline,
                                'updated_by': _currentUserId,
                                'updated_by_name': _currentUserName ?? 'Unknown User',
                              });
                            });

                            _saveHistoryToCache();
                            
                            // Try to fetch data in background to stay synced if online
                            _fetchAllData();

                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(isOffline ? "Saved offline. Please sync later." : "Barcode generated and saved successfully!"),
                                  backgroundColor: isOffline ? Colors.orange.shade800 : Colors.green.shade700,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          }
                        },
                        icon: Icon(Icons.crop_free, color: isDraft ? Colors.grey.shade600 : Colors.white, size: 20),
                        // WRAPPED IN FITTEDBOX TO PREVENT HORIZONTAL OVERFLOW ON SMALL SCREENS
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'GENERATE',
                            style: TextStyle(color: isDraft ? Colors.grey.shade600 : Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDraft ? Colors.grey.shade300 : Colors.green.shade800,
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start, // Align to top if wrapping
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black45, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16), // Added spacing
          // WRAPPED IN EXPANDED TO PREVENT HORIZONTAL OVERFLOW
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right, // Maintain right alignment
              style: TextStyle(color: valueColor ?? Colors.black87, fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';
    try {
      final DateTime dt = dateValue is String ? DateTime.parse(dateValue) : dateValue as DateTime;
      return DateFormat('MMM dd, yyyy • hh:mm a').format(dt);
    } catch (e) {
      return dateValue.toString();
    }
  }

  String _getUserNameById(dynamic userId) {
    if (userId == null) return 'Unknown';
    try {
      // Search for user in the _users list by matching user_id
      final user = _users.firstWhere((u) => u['user_id'].toString() == userId.toString(), orElse: () => null);

      if (user != null) {
        final String fname = (user['user_fname'] ?? '').toString();
        final String lname = (user['user_lname'] ?? '').toString();
        final String full = ('$fname $lname').trim();
        if (full.isNotEmpty) return full;
        return user['user_fname']?.toString() ?? 'Unknown';
      }
      return 'Unknown User';
    } catch (e) {
      return 'Unknown';
    }
  }

  // --- UPDATE BUNDLE WITH USER INFO IN API ---
  Future<void> _updateBundleUserInfo(dynamic bundleId, bool hasExistingBarcode) async {
    if (_currentUserId == null) return;

    try {
      final updateData = {'updated_by': _currentUserId, 'updated_at': DateTime.now().toIso8601String()};

      final response = await http
          .patch(Uri.parse('http://192.168.0.143:8056/items/product_bundles/$bundleId'), headers: {'Content-Type': 'application/json'}, body: json.encode(updateData))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Bundle user info updated successfully for bundle $bundleId');
      } else {
        debugPrint('⚠️ Failed to update bundle user info: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Error updating bundle user info: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      drawer: const AppDrawer(currentPage: 'Bundle'),
      endDrawer: HistoryDrawer(
        historyLogs: _historyLogs,
        onClear: _clearHistory,
        onSync: _syncOfflineItems, // --- PASSED SYNC LOGIC ---
        isSyncing: _isSyncing,     // --- PASSED SYNC STATE ---
        onItemTap: (logItem) {
          Navigator.pop(context);

          dynamic targetBundle;
          try {
            // --- TYPE-SAFE DRAWER TAP ---
            targetBundle = _bundles.firstWhere((b) => b['id'].toString() == logItem['bundle_id'].toString() || b['bundle_sku'] == logItem['sku']);
          } catch (e) {
            targetBundle = null;
          }

          if (targetBundle != null) {
            _showBundleDetails(targetBundle);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bundle details no longer available or syncing.")));
          }
        },
      ),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF388E3C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Bundle Barcoding',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              tooltip: 'Change History',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => PrintScreen(allProducts: _filteredBundles)));
        },
        backgroundColor: const Color(0xFF1B5E20),
        elevation: 4,
        tooltip: 'Batch Print Labels',
        child: const Icon(Icons.print, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return Center(child: CircularProgressIndicator(color: Colors.green.shade800));

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _initializeOfflineFirstData(); // Use the new init function to check cache again
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Text("Retry", style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: SearchWidget(hintText: "Search name, ID, or SKU...", onChanged: _runSearch),
        ),
        Expanded(
          child: _filteredBundles.isEmpty
              ? const Center(
                  child: Text("No matching bundles found.", style: TextStyle(color: Colors.black54, fontSize: 16)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredBundles.length,
                  itemBuilder: (context, index) {
                    final bundle = _filteredBundles[index];
                    return _buildBundleCard(bundle);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBundleCard(Map<String, dynamic> bundle) {
    final String statusText = bundle['status'] ?? 'Draft';
    final bool isApproved = statusText.toLowerCase() == 'approved';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ListTile(
        onTap: () => _showBundleDetails(bundle),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle),
          child: const Icon(Icons.inventory_2, color: Colors.green),
        ),
        title: Text(
          bundle['bundle_name'] ?? 'Unknown Bundle',
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
          maxLines: 2, // ADDED SAFETY FOR LONG TITLES
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text("SKU: ${bundle['bundle_sku'] ?? 'N/A'}", style: const TextStyle(color: Colors.black54, fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isApproved ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isApproved ? Colors.green.shade100 : Colors.orange.shade200),
              ),
              child: Text(
                statusText,
                style: TextStyle(color: isApproved ? Colors.green.shade700 : Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.qr_code_scanner, color: Colors.green.shade800),
          onPressed: () => _showBundleDetails(bundle),
        ),
      ),
    );
  }
}