import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'products.dart'; 

void main() {
  runApp(const MaterialApp(
    home: LoginPage(),
    debugShowCheckedModeBanner: false,
  ));
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false; // New state variable
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  // Load saved credentials from local storage
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emailController.text = prefs.getString('remembered_email') ?? '';
      _passwordController.text = prefs.getString('remembered_password') ?? '';
      _rememberMe = prefs.getBool('remember_me') ?? false;
    });
  }

  // Save or clear credentials based on the checkbox status
  Future<void> _handleRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('remembered_email', _emailController.text.trim());
      await prefs.setString('remembered_password', _passwordController.text.trim());
      await prefs.setBool('remember_me', true);
    } else {
      await prefs.remove('remembered_email');
      await prefs.remove('remembered_password');
      await prefs.setBool('remember_me', false);
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _errorMessage = null);

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = "Please fill in all fields.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    
    String? lockoutStr = prefs.getString('lockout_time_$email');
    if (lockoutStr != null) {
      final lockoutTime = DateTime.parse(lockoutStr);
      final difference = DateTime.now().difference(lockoutTime);
      if (difference.inMinutes < 5) {
        int remaining = 5 - difference.inMinutes;
        setState(() => _errorMessage = "Account locked. Try again in $remaining mins.");
        return;
      } else {
        await prefs.remove('lockout_time_$email');
        await prefs.remove('failed_attempts_$email');
      }
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.get(Uri.parse('http://192.168.0.143:8056/items/user'));

      if (response.statusCode == 200) {
        final List users = json.decode(response.body)['data'];
        
        final user = users.cast<Map<String, dynamic>?>().firstWhere(
          (u) => u?['user_email'] == email,
          orElse: () => null,
        );

        if (user == null) {
          setState(() => _errorMessage = "Account not found.");
        } else if (user['user_password'] == password) {
          // Success! 
          await _handleRememberMe(); // Save credentials if checked
          await prefs.remove('failed_attempts_$email');
          await prefs.remove('lockout_time_$email');
          
          if (!mounted) return;
          
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (context) => const ProductsScreen())
          );
        } else {
          int attempts = (prefs.getInt('failed_attempts_$email') ?? 0) + 1;
          await prefs.setInt('failed_attempts_$email', attempts);

          if (attempts >= 3) {
            await prefs.setString('lockout_time_$email', DateTime.now().toIso8601String());
            setState(() => _errorMessage = "3 failed attempts. Account Locked.");
          } else {
            setState(() => _errorMessage = "Invalid password. Attempt $attempts/3");
          }
        }
      } else {
        setState(() => _errorMessage = "Server error: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _errorMessage = "Connection error. Is your API running?");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF1976D2), Color(0xFF64B5F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                padding: const EdgeInsets.all(28.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.barcode_reader, size: 50, color: Colors.blue.shade900),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Products Barcoding",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      ),

                    _buildTextField(
                      controller: _emailController,
                      label: "Email Address",
                      icon: Icons.email_outlined,
                      type: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _passwordController,
                      label: "Password",
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      obscure: _obscurePassword,
                      onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    
                    // --- REMEMBER ME CHECKBOX ---
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
                            setState(() => _rememberMe = value ?? false);
                          },
                          activeColor: Colors.blue.shade900,
                        ),
                        const Text("Remember Me", style: TextStyle(fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 15),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade900,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('SIGN IN', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggle,
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue.shade700),
        suffixIcon: isPassword 
          ? IconButton(
              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: onToggle,
            ) 
          : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}