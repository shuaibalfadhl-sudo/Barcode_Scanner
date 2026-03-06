import 'package:flutter/material.dart';
import 'pages/products.dart';
import 'bundle/index.dart';
// Import for the logout redirect
import 'login.dart'; 
// --- 1. IMPORT YOUR NEW DRAWER ---
import 'widgets/drawer.dart'; 

class ManagementHubScreen extends StatelessWidget {
  const ManagementHubScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Standardizing the Light Theme background
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8), // Light grey background
      
      // --- 2. ADD THE DRAWER HERE (Pass 'Dashboard' so it turns Blue) ---
      drawer: const AppDrawer(currentPage: 'Dashboard'), 

      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1), // Rich blue to match your screenshot
        elevation: 0,
        
        // --- 3. THIS MAKES THE HAMBURGER ICON WHITE ---
        iconTheme: const IconThemeData(color: Colors.white), 
        
        title: const Text(
          'Product Barcoding',
          style: TextStyle(
            fontSize: 24, // Slightly scaled down to match the cleaner look
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white), // Changed to white for contrast
            onPressed: () {
              // --- LOGOUT ROUTING ---
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (Route<dynamic> route) => false,
              );
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan and manage your product and bundle barcodes.',
              style: TextStyle(color: Colors.black54, fontSize: 16), // Darker grey for readability on light BG
            ),
            const SizedBox(height: 30),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.9, 
                children: [
                  // 1. Product Barcoding Card
                  DashboardCard(
                    title: 'Product Barcoding',
                    icon: Icons.qr_code_scanner,
                    iconColor: Colors.blueAccent,
                    onTap: () {
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (context) => const ProductsScreen())
                      );
                    },
                  ),
                  // 2. Bundle Barcoding Card
                  DashboardCard(
                    title: 'Bundle Barcoding',
                    icon: Icons.inventory_2,
                    iconColor: Colors.orangeAccent, // Changed to orange/warm tone to complement the blue
                    onTap: () {
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (context) => const BundleScreen())
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Reusable Widget for the Grid Cards ---
class DashboardCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const DashboardCard({
    Key? key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // Crisp white cards
        borderRadius: BorderRadius.circular(20), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05), // Subtle drop shadow for depth
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          splashColor: iconColor.withOpacity(0.15), 
          highlightColor: iconColor.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Circular Icon Container
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withOpacity(0.1), // Very light background for the icon
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                // Card Title
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87, // Dark text for the light card
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}