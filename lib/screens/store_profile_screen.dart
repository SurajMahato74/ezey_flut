import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class StoreProfileScreen extends StatefulWidget {
  const StoreProfileScreen({super.key});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final TextEditingController _storeNameController = TextEditingController(text: "Everest Fresh Groceries");
  final TextEditingController _storeDescriptionController = TextEditingController(
    text: "Your one-stop shop for fresh, locally-sourced vegetables and groceries in Kathmandu. Delivered to your doorstep with Ezeyway."
  );
  final TextEditingController _deliveryTimeController = TextEditingController(text: "30 Mins");
  final TextEditingController _minimumOrderController = TextEditingController(text: "250");
  final TextEditingController _contactNumberController = TextEditingController(text: "+977 9841234567");
  final TextEditingController _storeAddressController = TextEditingController(text: "Boudha, Kathmandu");
  
  bool _isStoreOnline = true;

  @override
  void dispose() {
    _storeNameController.dispose();
    _storeDescriptionController.dispose();
    _deliveryTimeController.dispose();
    _minimumOrderController.dispose();
    _contactNumberController.dispose();
    _storeAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: Column(
        children: [
          // Top App Bar
          Container(
            padding: const EdgeInsets.only(top: 44, left: 16, right: 16, bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.backgroundLight.withOpacity(0.8),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.black,
                    size: 24,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'My Store Profile',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48), // For balance
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Profile Header
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(64),
                            image: const DecorationImage(
                              image: NetworkImage(
                                'https://lh3.googleusercontent.com/aida-public/AB6AXuDHLieNy9pbYqzmyghGEIpg6Nn27-qQZ15bVDYkxR1p_AvwuPxwGPc3oCpWV4MhiXaW_6zlZmLk9QcdrYMytjsKkVa9DRaZWx2MEqDSMz3WbxkCBcbDqAa1qJ9crfvP1ZKOxGr8cNnDDaLwyWMYEQ63NbrnPOTlJkfCCuI3rDUyB7NChc_MJ0xWTK70xvzaicwmi1Um3JdKozx9gAv4ezWmTIstTUbBHZu_WBSuyfNV1xG-dbuByT6dJpUA-4_YipxzHIulhRVmVUxe',
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () {
                              // Handle logo edit
                              _showEditLogoDialog();
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.black,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Core Store Details
                  _buildSectionTitle('Store Information'),
                  const SizedBox(height: 16),

                  _buildTextField(
                    controller: _storeNameController,
                    label: 'Store Name',
                  ),

                  const SizedBox(height: 16),

                  _buildTextArea(
                    controller: _storeDescriptionController,
                    label: 'Store Description',
                    minLines: 4,
                  ),

                  const SizedBox(height: 32),

                  // Operational Status
                  _buildOperationalStatus(),

                  const SizedBox(height: 32),

                  // Order & Delivery Info
                  _buildSectionTitle('Order & Delivery'),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _deliveryTimeController,
                          label: 'Avg. Delivery Time',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextField(
                          controller: _minimumOrderController,
                          label: 'Minimum Order (Rs.)',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Contact & Location
                  _buildSectionTitle('Contact & Location'),
                  const SizedBox(height: 16),

                  _buildTextField(
                    controller: _contactNumberController,
                    label: 'Contact Number',
                    keyboardType: TextInputType.phone,
                  ),

                  const SizedBox(height: 16),

                  _buildTextField(
                    controller: _storeAddressController,
                    label: 'Store Address',
                  ),

                  const SizedBox(height: 16),

                  // Map View Component
                  _buildMapView(),

                  const SizedBox(height: 120), // Space for bottom button
                ],
              ),
            ),
          ),
        ],
      ),

      // Action Button
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.backgroundLight.withOpacity(0.8),
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Save Changes',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Colors.black,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.black.withOpacity(0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.black.withOpacity(0.2),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppTheme.primaryColor,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextArea({
    required TextEditingController controller,
    required String label,
    required int minLines,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          minLines: minLines,
          maxLines: null,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Colors.black,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.black.withOpacity(0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.black.withOpacity(0.2),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppTheme.primaryColor,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOperationalStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.storefront,
              color: Colors.black,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Store is ${_isStoreOnline ? "Online" : "Offline"}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _isStoreOnline = !_isStoreOnline;
              });
            },
            child: Container(
              width: 51,
              height: 31,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15.5),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: _isStoreOnline ? Alignment.centerRight : Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 3,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Store Location',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: const DecorationImage(
              image: NetworkImage(
                'https://lh3.googleusercontent.com/aida-public/AB6AXuD85TIS5SdnDSsAlRDeoDzsFSmkWYaXnBQd5AVlCBArQ4nNxartDgqb-UjTc8FZIzZW3LZPd0yTpjGaxM7VS96p_74J4JBf3kR3j_OmZkn9tn-ze7__j8cYs93S4iB7TDxunybxEZ7mAg2st0CquuPSAJYiLSxcIvIMlAT0OQLw2NBVXSE8_8_cegN7Bk1mydBl4UwCB7u4_e4zElCmvtA9PC-lt10uElpLpbM4HBpkrHiYblfNXsrwDZBZ_gdQ2L-M5JHxwT7Tr_-i',
              ),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              // Handle map update
              _showMapUpdateDialog();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black.withOpacity(0.1),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Update on Map',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditLogoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Edit Store Logo',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(
                  'Take Photo',
                  style: GoogleFonts.plusJakartaSans(),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // Handle camera
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(
                  'Choose from Gallery',
                  style: GoogleFonts.plusJakartaSans(),
                ),
                onTap: () {
                  Navigator.pop(context);
                  // Handle gallery
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMapUpdateDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Update Store Location',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Would you like to update your store location on the map?',
            style: GoogleFonts.plusJakartaSans(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.plusJakartaSans(),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Handle map update
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Location updated successfully!'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.black,
              ),
              child: Text(
                'Update',
                style: GoogleFonts.plusJakartaSans(),
              ),
            ),
          ],
        );
      },
    );
  }

  void _saveChanges() {
    // Validate and save changes
    if (_storeNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store name is required')),
      );
      return;
    }

    // Here you would typically save to a database or API
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Store profile updated successfully!'),
        backgroundColor: Colors.green,
      ),
    );

    // Navigate back or show success
    Navigator.pop(context);
  }
}