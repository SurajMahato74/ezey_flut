import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/auth_service.dart';
import '../config.dart' as appConfig;

class VendorProofUploadDialog extends StatefulWidget {
  final Map<String, dynamic> refund;
  final VoidCallback onProofUploaded;

  const VendorProofUploadDialog({
    super.key,
    required this.refund,
    required this.onProofUploaded,
  });

  @override
  State<VendorProofUploadDialog> createState() => _VendorProofUploadDialogState();
}

class _VendorProofUploadDialogState extends State<VendorProofUploadDialog> {
  List<XFile> _selectedImages = [];
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages = images;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking images: $e')),
      );
    }
  }

  Future<void> _uploadProofAndProcess() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload at least one proof document')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final token = AuthService().token;
      if (token == null) return;

      // Upload proof documents
      for (XFile image in _selectedImages) {
        await _uploadDocument(widget.refund['id'], image);
      }

      // Mark refund as processed
      final response = await http.post(
        Uri.parse('${appConfig.Config.baseUrl}/vendor/refunds/${widget.refund['id']}/process/'),
        headers: {
          'Authorization': 'Token $token',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: json.encode({
          'status': 'processed',
          'admin_notes': 'Refund processed by vendor with proof documents'
        }),
      );

      if (response.statusCode == 200) {
        Navigator.pop(context);
        widget.onProofUploaded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refund processed successfully with proof'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Failed to process refund');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _uploadDocument(int refundId, XFile file) async {
    try {
      final token = AuthService().token;
      if (token == null) return;
      
      final bytes = await file.readAsBytes();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${appConfig.Config.baseUrl}/refunds/$refundId/upload-document/'),
      );

      request.headers['Authorization'] = 'Token $token';
      request.headers['ngrok-skip-browser-warning'] = 'true';
      request.files.add(http.MultipartFile.fromBytes(
        'document', 
        bytes,
        filename: file.name,
      ));

      await request.send();
    } catch (e) {
      print('Error uploading document: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.upload_file, color: Color(0xFFFFD60A)),
                const SizedBox(width: 8),
                Text(
                  'Upload Refund Proof',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Text(
              'Upload proof documents before marking refund as processed',
              style: TextStyle(color: Colors.grey[300], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            GestureDetector(
              onTap: _pickImages,
              child: Container(
                height: 120,
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
                            Icon(Icons.add_photo_alternate, color: Colors.grey, size: 40),
                            SizedBox(height: 8),
                            Text('Tap to add proof images', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _selectedImages.length,
                        itemBuilder: (context, index) {
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: kIsWeb 
                                  ? NetworkImage(_selectedImages[index].path) as ImageProvider
                                  : FileImage(File(_selectedImages[index].path)) as ImageProvider,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            
            if (_selectedImages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_selectedImages.length} proof document(s) selected',
                  style: const TextStyle(color: Color(0xFFFFD60A), fontSize: 12),
                ),
              ),
            
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isUploading ? null : () => Navigator.pop(context),
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
                    onPressed: _isUploading ? null : _uploadProofAndProcess,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Upload & Process'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}