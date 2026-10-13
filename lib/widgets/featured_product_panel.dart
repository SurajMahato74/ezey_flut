import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../services/auth_service.dart';

/// Uses the paid promotion endpoints; never writes the product's featured flag.
class FeaturedProductPanel extends StatefulWidget {
  final int productId;
  final bool featured;
  final http.Client? client;
  const FeaturedProductPanel(
      {super.key, required this.productId, this.featured = false, this.client});

  @override
  State<FeaturedProductPanel> createState() => _FeaturedProductPanelState();
}

class _FeaturedProductPanelState extends State<FeaturedProductPanel> {
  bool _busy = true;
  bool _loaded = false;
  bool? _savedFeatured;
  String? _error;
  String? _message;
  List<Map<String, dynamic>> _packages = [];
  Map<String, dynamic>? _purchase;
  Map<String, dynamic>? _selected;
  bool _canModify = false;
  DateTime _serverToday = DateUtils.dateOnly(DateTime.now());
  DateTime _start = DateUtils.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _request(String path,
      [Map<String, dynamic>? data]) async {
    final token = context.read<AuthService>().token;
    if (token == null) throw Exception('Please sign in again.');
    final headers = {
      'Authorization': 'Token $token',
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true'
    };
    final uri = Uri.parse('${Config.baseUrl}/$path');
    final response = data == null
        ? await (widget.client?.get(uri, headers: headers) ??
            http.get(uri, headers: headers))
        : await (widget.client
                ?.post(uri, headers: headers, body: jsonEncode(data)) ??
            http.post(uri, headers: headers, body: jsonEncode(data)));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error'] ??
          body['detail'] ??
          'Could not update featured package.');
    }
    return body;
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _loaded = false;
    });
    try {
      final info =
          await _request('products/${widget.productId}/featured-info/');
      final product = await _request('products/${widget.productId}/');
      final packages = await _request('featured-packages/');
      if (!mounted) return;
      setState(() {
        _savedFeatured =
            product['featured'] is bool ? product['featured'] as bool : null;
        _purchase = info['current_purchase'] == null
            ? null
            : Map<String, dynamic>.from(info['current_purchase']);
        _canModify = info['can_modify'] == true;
        _serverToday =
            DateTime.tryParse(info['server_date']?.toString() ?? '') ??
                DateUtils.dateOnly(DateTime.now());
        _packages = List<Map<String, dynamic>>.from(packages['packages'] ?? []);
        _selected = null;
        if (_purchase != null) {
          _start = DateTime.parse(_purchase!['start_date']);
          if (_start.isBefore(_serverToday)) _start = _serverToday;
        }
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final date = DateFormat('yyyy-MM-dd').format(_start);
      final result = _purchase != null
          ? await _request('products/${widget.productId}/reschedule-featured/',
              {'start_date': date})
          : await _request('featured-packages/purchase/', {
              'product_id': widget.productId,
              'package_id': _selected!['id'],
              'start_date': date
            });
      if (!mounted) return;
      setState(
          () => _message = result['message'] ?? 'Featured package updated.');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSchedule = _loaded && (_purchase == null || _canModify);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Flash promotion',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Promote this product in Flash with a paid featured package. The package price is deducted from your vendor wallet.'),
              if (_busy) const LinearProgressIndicator(),
              if (_loaded)
                Text(_savedFeatured == true
                    ? 'Saved featured status: On'
                    : _savedFeatured == false
                        ? 'Saved featured status: Off — this product is not currently included in Flash.'
                        : 'Saved featured status could not be confirmed.'),
              if (_message != null) Text(_message!),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Reload featured status')),
              ],
              if (_loaded && _purchase != null) ...[
                Text(
                    '${_purchase!['package_name']}\n${_purchase!['start_date']} to ${_purchase!['end_date']}'),
                Text(_canModify
                    ? 'You can change the start date or feature now using your remaining paid time. The end date is calculated automatically. No additional charge.'
                    : _savedFeatured == false
                        ? 'Your package is purchased, but this product is not marked featured. Please contact support to check your paid promotion. Do not purchase another package.'
                        : 'This package schedule is locked. Its dates cannot be edited.'),
                TextButton.icon(
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check status again'),
                ),
              ],
              if (_loaded && _purchase == null) ...[
                if (_packages.isEmpty)
                  const Text('No featured packages are currently available.'),
                ..._packages.map((package) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selected?['id'] == package['id'],
                      onChanged: _busy
                          ? null
                          : (_) => setState(() => _selected = package),
                      title:
                          Text('${package['name']} — Rs. ${package['amount']}'),
                      subtitle: Text(
                          '${package['duration_days']} days${package['description'] == null ? '' : '\n${package['description']}'}'),
                    )),
              ],
              if (canSchedule) ...[
                if (_purchase != null)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _start = _serverToday);
                            _save();
                          },
                    icon: const Icon(Icons.star),
                    label: const Text('Feature now (no charge)'),
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                      'Start date: ${DateFormat('yyyy-MM-dd').format(_start)}'),
                  onPressed: _busy
                      ? null
                      : () async {
                          final today = _serverToday;
                          final date = await showDatePicker(
                              context: context,
                              initialDate:
                                  _start.isBefore(today) ? today : _start,
                              firstDate: today,
                              lastDate: DateTime(today.year + 10));
                          if (date != null && mounted) {
                            setState(() => _start = date);
                          }
                        },
                ),
                FilledButton(
                  onPressed: _busy || (_purchase == null && _selected == null)
                      ? null
                      : _save,
                  child: Text(_purchase != null
                      ? 'Update dates (no charge)'
                      : _selected == null
                          ? 'Select a featured package'
                          : 'Pay Rs. ${_selected!['amount']} and feature product'),
                ),
              ],
            ]),
      ),
    );
  }
}
