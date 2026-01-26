import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../services/auth_service.dart';
import '../config.dart' as appConfig;

class RefundRequestDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onRefundRequested;

  const RefundRequestDialog({
    super.key,
    required this.order,
    required this.onRefundRequested,
  });

  @override
  State<RefundRequestDialog> createState() => _RefundRequestDialogState();
}

class _RefundRequestDialogState extends State<RefundRequestDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _esewaController = TextEditingController();
  final TextEditingController _khaltiController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountNumberController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  
  String _refundMethod = 'esewa';
  List<File> _selectedImages = [];
  bool _isSubmitting = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.order['total_amount']?.toString() ?? '0';
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages = images.map((xFile) => File(xFile.path)).toList();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking images: $e')),
      );
    }
  }

  Future<void> _submitRefundRequest() async {
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a reason for refund')),
      );
      return;
    }

    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload at least one supporting document')),
      );
      return;
    }

    print('🔵 Starting refund request submission');
    print('🔵 Selected images count: ${_selectedImages.length}');
    setState(() => _isSubmitting = true);

    try {
      final token = AuthService().token;
      if (token == null) {
        print('❌ No token found');
        return;
      }

      print('🔵 Token found, creating refund request');
      // Create refund request
      final refundData = {
        'refund_type': 'full',
        'requested_amount': double.tryParse(_amountController.text) ?? 0.0,
        'reason': _reasonController.text.trim(),
        'customer_notes': _notesController.text.trim(),
        'refund_method': _refundMethod,
        if (_refundMethod == 'esewa') 'esewa_number': _esewaController.text.trim(),
        if (_refundMethod == 'khalti') 'khalti_number': _khaltiController.text.trim(),
        if (_refundMethod == 'bank') ...{
          'bank_account_name': _bankNameController.text.trim(),
          'bank_account_number': _accountNumberController.text.trim(),
          'bank_branch': _branchController.text.trim(),
        },
      };

      print('🔵 Refund data: $refundData');
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/orders/${widget.order['id']}/refund/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: json.encode(refundData),
      );

      print('🔵 Refund request response status: ${response.statusCode}');
      print('🔵 Refund request response body: ${response.body}');

      if (response.statusCode == 201) {
        final refundResponse = json.decode(response.body);
        print('🔵 Full response object: $refundResponse');
        print('🔵 Response type: ${refundResponse.runtimeType}');
        print('🔵 Refund object: ${refundResponse['refund']}');
        print('🔵 Refund type: ${refundResponse['refund'].runtimeType}');
        
        final refundData = refundResponse['refund'];
        final refundId = refundData != null ? (refundData['id'] as num?)?.toInt() : null;
        
        print('✅ Refund created with ID: $refundId');
        
        if (refundId != null) {
          print('🔵 Starting image upload for ${_selectedImages.length} images');
          // Upload images
          for (int i = 0; i < _selectedImages.length; i++) {
            print('🔵 Uploading image ${i + 1}/${_selectedImages.length}');
            await _uploadDocument(refundId, _selectedImages[i]);
          }
          print('✅ All images uploaded');
        } else {
          print('❌ No refund ID returned');
        }

        if (mounted) {
          Navigator.pop(context);
          widget.onRefundRequested();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Refund request submitted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('❌ Failed to create refund: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to submit refund request: ${response.body}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      print('❌ Exception during refund submission: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _uploadDocument(int refundId, File file) async {
    try {
      final token = AuthService().token;
      if (token == null) {
        print('❌ No token for upload');
        return;
      }

      print('🔵 Uploading document to: ${appConfig.Config.baseUrl}/refunds/$refundId/upload-document/');
      print('🔵 File path: ${file.path}');
      print('🔵 File exists: ${await file.exists()}');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${appConfig.Config.baseUrl}/refunds/$refundId/upload-document/'),
      );

      request.headers['Authorization'] = 'Token $token';
      request.headers['ngrok-skip-browser-warning'] = 'true';
      request.files.add(await http.MultipartFile.fromPath('document', file.path));

      print('🔵 Sending upload request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('🔵 Upload response status: ${response.statusCode}');
      print('🔵 Upload response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Document uploaded successfully');
      } else {
        print('❌ Failed to upload document: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error uploading document: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Request Refund',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField('Refund Amount', _amountController, isNumber: true),
                    const SizedBox(height: 16),
                    _buildTextField('Reason for Refund', _reasonController, maxLines: 3),
                    const SizedBox(height: 16),
                    _buildTextField('Additional Notes', _notesController, maxLines: 2),
                    const SizedBox(height: 16),
                    
                    _buildRefundMethodSection(),
                    const SizedBox(height: 16),
                    
                    _buildImageUploadSection(),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.grey),
                      foregroundColor: Colors.grey,
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRefundRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD60A),
                      foregroundColor: Colors.black,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1, bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey[600]!),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFFFFD60A)),
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
          ),
        ),
      ],
    );
  }

  Widget _buildRefundMethodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Refund Method', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Column(
          children: [
            _buildMethodRadio('esewa', 'eSewa'),
            _buildMethodRadio('khalti', 'Khalti'),
            _buildMethodRadio('bank', 'Bank Transfer'),
          ],
        ),
        const SizedBox(height: 12),
        if (_refundMethod == 'esewa')
          _buildTextField('eSewa Number', _esewaController),
        if (_refundMethod == 'khalti')
          _buildTextField('Khalti Number', _khaltiController),
        if (_refundMethod == 'bank') ...[
          _buildTextField('Bank Account Name', _bankNameController),
          const SizedBox(height: 8),
          _buildTextField('Account Number', _accountNumberController),
          const SizedBox(height: 8),
          _buildTextField('Branch', _branchController),
        ],
      ],
    );
  }

  Widget _buildMethodRadio(String value, String label) {
    return RadioListTile<String>(
      value: value,
      groupValue: _refundMethod,
      onChanged: (val) => setState(() => _refundMethod = val!),
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      activeColor: const Color(0xFFFFD60A),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildImageUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Supporting Documents *', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickImages,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[600]!),
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF2A2A2A),
            ),
            child: _selectedImages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate, color: Colors.grey, size: 32),
                        SizedBox(height: 4),
                        Text('Tap to add images', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(8),
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 80,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: FileImage(_selectedImages[index]),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 12,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImages.removeAt(index);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
        if (_selectedImages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_selectedImages.length} image(s) selected',
              style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 12),
            ),
          ),
      ],
    );
  }
}