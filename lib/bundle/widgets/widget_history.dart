import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistoryDrawer extends StatelessWidget {
  final List<Map<String, dynamic>> historyLogs;
  final VoidCallback? onClear;
  final VoidCallback? onSync;
  final bool isSyncing;
  final Function(Map<String, dynamic>)? onItemTap;

  const HistoryDrawer({
    Key? key,
    required this.historyLogs,
    this.onClear,
    this.onSync,
    this.isSyncing = false,
    this.onItemTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Count how many items need syncing
    int unsyncedCount = historyLogs.where((item) => item['is_synced'] == false).length;

    return Drawer(
      backgroundColor: const Color(0xFFF4F7F9),
      child: Column(
        children: [
          // --- HEADER ---
          DrawerHeader(
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(color: Colors.green.shade800),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 50, color: Colors.white),
                  SizedBox(height: 8),
                  Text(
                    "Activity Log",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          // --- SYNC BAR (Only shows if there are offline items) ---
          if (unsyncedCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600, foregroundColor: Colors.white, elevation: 0),
                onPressed: isSyncing ? null : onSync,
                icon: isSyncing
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: Text(isSyncing ? "Syncing..." : "Sync $unsyncedCount Offline Items"),
              ),
            ),

          // --- HEADER CONTROLS ---
          if (historyLogs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${historyLogs.length} Activities",
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                    label: const Text("Clear", style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),

          // --- LOG LIST ---
          Expanded(
            child: historyLogs.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: historyLogs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _buildLogItem(context, historyLogs[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.history, size: 80, color: Colors.grey.withOpacity(0.3)),
        const SizedBox(height: 16),
        const Text('No history found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
      ],
    );
  }

  Widget _buildLogItem(BuildContext context, Map<String, dynamic> item) {
    // --- NORMALIZER ---
    // Safely handles data from both products.dart and index.dart
    final String itemName = item['product_name'] ?? item['name'] ?? item['bundle_name'] ?? 'Unknown Item';
    final String barcode = item['barcode'] ?? item['new_barcode'] ?? 'N/A';

    // Time Parsing
    final dynamic rawTime = item['time'] ?? item['timestamp'];
    final DateTime time =
        rawTime is String ? (DateTime.tryParse(rawTime) ?? DateTime.now()) : (rawTime ?? DateTime.now());

    // Flag Parsing (Handles products.dart booleans OR index.dart string actions)
    final String actionStr = (item['action'] ?? '').toString().toLowerCase();
    final bool isScanned = (item['is_scanned'] == true) || actionStr == 'scanned' || actionStr == 'scan';
    final bool isRescan = (item['is_rescan'] == true) || actionStr == 'rescan';
    final bool isGenerated = (item['is_generated'] == true) || actionStr == 'generate';
    final bool isRegenerated = (item['is_regenerated'] == true) || actionStr == 'regenerated';
    final bool isSynced = item['is_synced'] ?? true; // Default to true if missing

    // --- USER INFO ---
    final String? updatedByName = item['updated_by_name'] as String?;
    final String? updatedByFname = (item['updated_by_fname'] ?? item['user_fname']) as String?;
    final String? updatedByLname = (item['updated_by_lname'] ?? item['user_lname']) as String?;

    String userDisplay;
    if (updatedByName != null && updatedByName.trim().isNotEmpty) {
      // If server provided only first name but we have last name separately, combine them
      if (!updatedByName.contains(' ') && (updatedByLname?.trim().isNotEmpty ?? false)) {
        userDisplay = '${updatedByName.trim()} ${updatedByLname!.trim()}';
      } else {
        userDisplay = updatedByName.trim();
      }
    } else if ((updatedByFname?.trim().isNotEmpty ?? false) || (updatedByLname?.trim().isNotEmpty ?? false)) {
      userDisplay = '${updatedByFname ?? ''} ${updatedByLname ?? ''}'.trim();
    } else {
      userDisplay = 'Unknown User';
    }
    
    // --- UI DETERMINATION ---
    String tag = "NEW";
    Color color = Colors.blue;
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
              itemName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            child: Text(
              tag,
              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ),
          if (!isSynced)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: const Text(
                "UNSYNCED",
                style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Code: $barcode", style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          Text(
            "By: $userDisplay",
            style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w500),
          ),
          Text(DateFormat('MMM dd • hh:mm a').format(time),
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
      onTap: onItemTap != null ? () => onItemTap!(item) : null,
    );
  }
}