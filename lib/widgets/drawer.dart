import 'package:flutter/material.dart';
import '../pages/products.dart';
import '../bundle/index.dart'; 
import '../login.dart';
import '../index.dart'; 

// ... existing imports

class AppDrawer extends StatelessWidget {
  final String currentPage; 

  const AppDrawer({Key? key, required this.currentPage}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color primaryColor;
    Color secondaryColor;

    if (currentPage == 'Products' || currentPage == 'Dashboard') {
      primaryColor = const Color(0xFF0D47A1); 
      secondaryColor = const Color(0xFF1976D2); 
    } else {
      primaryColor = const Color(0xFF1B5E20); 
      secondaryColor = const Color(0xFF43A047); 
    }

    // Helper widget to build menu items with active state
    Widget buildMenuItem({
      required IconData icon,
      required String title,
      required String pageName,
      required VoidCallback onTap,
    }) {
      final bool isActive = currentPage == pageName;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          // Apply a subtle background color if active
          color: isActive ? primaryColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(
            icon, 
            color: isActive ? primaryColor : Colors.grey[600],
            size: isActive ? 26 : 24,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? primaryColor : Colors.black87,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              fontSize: 15,
            ),
          ),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    return Drawer(
      backgroundColor: const Color(0xFFF1F5F9),
      child: Column(
        children: [
          // --- Drawer Header ---
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 20, left: 20, right: 20,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, secondaryColor], 
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.admin_panel_settings, size: 40, color: primaryColor),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Management Hub',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Admin Panel',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          
          // --- Menu Items ---
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                buildMenuItem(
                  icon: Icons.dashboard,
                  title: 'Dashboard',
                  pageName: 'Dashboard',
                  onTap: () {
                    Navigator.pop(context);
                    if (currentPage != 'Dashboard') {
                      Navigator.pushReplacement(
                        context, 
                        MaterialPageRoute(builder: (context) => const ManagementHubScreen())
                      );
                    }
                  },
                ),
                buildMenuItem(
                  icon: Icons.qr_code_scanner,
                  title: 'Product Barcoding',
                  pageName: 'Products',
                  onTap: () {
                    Navigator.pop(context);
                    if (currentPage != 'Products') {
                      Navigator.pushReplacement(
                        context, 
                        MaterialPageRoute(builder: (context) => const ProductsScreen())
                      );
                    }
                  },
                ),
                buildMenuItem(
                  icon: Icons.inventory_2,
                  title: 'Bundle Barcoding',
                  pageName: 'Bundle',
                  onTap: () {
                    Navigator.pop(context);
                    if (currentPage != 'Bundle') {
                      Navigator.pushReplacement(
                        context, 
                        MaterialPageRoute(builder: (context) => const BundleScreen())
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          
          const Divider(height: 1, thickness: 0.5),
          
          // --- Logout Button ---
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (Route<dynamic> route) => false,
              );
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 10),
        ],
      ),
    );
  }
}