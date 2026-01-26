import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../config.dart' as appConfig;

class CompanyInformationScreen extends StatefulWidget {
  const CompanyInformationScreen({super.key});

  @override
  State<CompanyInformationScreen> createState() => _CompanyInformationScreenState();
}

class _CompanyInformationScreenState extends State<CompanyInformationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  Map<String, dynamic>? _vendorData;
  
  // Form controllers
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _deliveryRadiusController = TextEditingController();
  final TextEditingController _minOrderController = TextEditingController();
  
  List<String> _selectedCategories = [];
  List<String> _availableCategories = [];
  bool _isActive = false;
  
  // Operating hours
  final Map<String, Map<String, dynamic>> _operatingHours = {
    'monday': {'open': '06:00', 'close': '21:00', 'closed': false},
    'tuesday': {'open': '06:00', 'close': '21:00', 'closed': false},
    'wednesday': {'open': '06:00', 'close': '21:00', 'closed': false},
    'thursday': {'open': '06:00', 'close': '21:00', 'closed': false},
    'friday': {'open': '06:00', 'close': '21:00', 'closed': false},
    'saturday': {'open': '06:00', 'close': '21:00', 'closed': false},
    'sunday': {'open': '07:00', 'close': '20:00', 'closed': false},
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _deliveryRadiusController.dispose();
    _minOrderController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    await Future.wait([
      _fetchVendorData(),
      _fetchCategories(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _fetchVendorData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results']?.isNotEmpty == true) {
          _vendorData = data['results'][0];
          _populateFields();
        }
      }
    } catch (e) {
      print('Error fetching vendor data: $e');
    }
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await http.get(
        Uri.parse('${appConfig.Config.baseUrl}/categories/'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['categories'] is List) {
          setState(() {
            _availableCategories = List<String>.from(
              data['categories'].map((cat) => cat['name'])
            );
          });
        }
      }
    } catch (e) {
      print('Error fetching categories: $e');
    }
  }

  void _populateFields() {
    if (_vendorData == null) return;
    
    _businessNameController.text = _vendorData!['business_name'] ?? '';
    _ownerNameController.text = _vendorData!['owner_name'] ?? '';
    _deliveryRadiusController.text = _vendorData!['delivery_radius']?.toString() ?? '';
    _minOrderController.text = _vendorData!['min_order_amount']?.toString() ?? '';
    
    _selectedCategories = List<String>.from(_vendorData!['categories'] ?? []);
    _isActive = _vendorData!['is_active'] ?? false;
    
    // Populate operating hours
    final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    for (String day in days) {
      _operatingHours[day] = {
        'open': _vendorData!['${day}_open'] ?? '06:00',
        'close': _vendorData!['${day}_close'] ?? '21:00',
        'closed': _vendorData!['${day}_closed'] ?? false,
      };
    }
  }

  Future<void> _saveData() async {
    if (_vendorData == null) return;
    
    setState(() => _isSaving = true);
    
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final updateData = {
        'business_name': _businessNameController.text,
        'owner_name': _ownerNameController.text,
        'delivery_radius': double.tryParse(_deliveryRadiusController.text),
        'min_order_amount': _minOrderController.text,
        'categories': _selectedCategories,
      };

      // Add operating hours
      _operatingHours.forEach((day, hours) {
        updateData['${day}_open'] = hours['closed'] ? null : hours['open'];
        updateData['${day}_close'] = hours['closed'] ? null : hours['close'];
        updateData['${day}_closed'] = hours['closed'];
      });

      final response = await http.patch(
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/${_vendorData!['id']}/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode(updateData),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Company information updated successfully!'),
            backgroundColor: Color(0xFFFFD60A),
          ),
        );
        setState(() => _isEditing = false);
        _fetchVendorData();
      } else {
        throw Exception('Failed to update');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleStatus() async {
    if (_vendorData == null) return;
    
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    try {
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/vendor-profiles/${_vendorData!['id']}/toggle-status/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'is_active': !_isActive}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _isActive = data['vendor']['is_active']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to ${_isActive ? 'Active' : 'Inactive'}'),
            backgroundColor: const Color(0xFFFFD60A),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error toggling status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.homeBackgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.homeBackgroundDark.withOpacity(0.9),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Company Information',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isEditing ? _saveData : () => setState(() => _isEditing = true),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppTheme.primaryColor,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          _isEditing ? Icons.save : Icons.edit,
                          color: AppTheme.primaryColor,
                        ),
                ),
              ],
            ),
          ),

          // Company Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF18181B),
              border: Border(bottom: BorderSide(color: Color(0xFF54533b))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey[800],
                  child: const Icon(Icons.business, color: Colors.white54, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _businessNameController.text.isNotEmpty 
                            ? _businessNameController.text 
                            : 'Business Name',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _ownerNameController.text.isNotEmpty 
                            ? _ownerNameController.text 
                            : 'Owner Name',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: const Color(0xFFbab89c),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Status: ',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          Switch(
                            value: _isActive,
                            onChanged: _isEditing ? (_) => _toggleStatus() : null,
                            activeThumbColor: AppTheme.primaryColor,
                          ),
                          Text(
                            _isActive ? 'Active' : 'Inactive',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: _isActive ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          Container(
            color: AppTheme.homeBackgroundDark,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primaryColor,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: const Color(0xFFbab89c),
              tabs: const [
                Tab(text: 'Business Details'),
                Tab(text: 'Operating Hours'),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBusinessTab(),
                _buildTimingTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('Business Name', _businessNameController),
          const SizedBox(height: 16),
          _buildTextField('Owner Name', _ownerNameController),
          const SizedBox(height: 16),
          _buildTextField('Delivery Radius (km)', _deliveryRadiusController),
          const SizedBox(height: 16),
          _buildTextField('Minimum Order Amount', _minOrderController),
          const SizedBox(height: 24),
          
          // Categories
          Text(
            'Business Categories',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableCategories.map((category) {
              final isSelected = _selectedCategories.contains(category);
              return GestureDetector(
                onTap: _isEditing ? () {
                  setState(() {
                    if (isSelected) {
                      _selectedCategories.remove(category);
                    } else {
                      _selectedCategories.add(category);
                    }
                  });
                } : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryColor : const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryColor : const Color(0xFF54533b),
                    ),
                  ),
                  child: Text(
                    category,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operating Hours',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          ..._operatingHours.entries.map((entry) {
            final day = entry.key;
            final hours = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF54533b)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          day.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Switch(
                        value: !hours['closed'],
                        onChanged: _isEditing ? (value) {
                          setState(() {
                            _operatingHours[day]!['closed'] = !value;
                          });
                        } : null,
                        activeThumbColor: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                  if (!hours['closed']) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimeField('Open', hours['open'], (value) {
                            setState(() {
                              _operatingHours[day]!['open'] = value;
                            });
                          }),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTimeField('Close', hours['close'], (value) {
                            setState(() {
                              _operatingHours[day]!['close'] = value;
                            });
                          }),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: _isEditing,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF54533b)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF54533b)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primaryColor),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF54533b)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeField(String label, String value, Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: const Color(0xFFbab89c),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _isEditing ? () async {
            final TimeOfDay? time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour: int.parse(value.split(':')[0]),
                minute: int.parse(value.split(':')[1]),
              ),
            );
            if (time != null) {
              onChanged('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}');
            }
          } : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF54533b)),
            ),
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}