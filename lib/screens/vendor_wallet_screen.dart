import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class VendorWalletScreen extends StatefulWidget {
  const VendorWalletScreen({super.key});

  @override
  State<VendorWalletScreen> createState() => _VendorWalletScreenState();
}

class Transaction {
  final int id;
  final String? orderNumber;
  final String description;
  final double amount;
  final DateTime timestamp;
  final String transactionType;
  final String status;

  Transaction({
    required this.id,
    this.orderNumber,
    required this.description,
    required this.amount,
    required this.timestamp,
    required this.transactionType,
    required this.status,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    String? orderNum;
    if (json['description'] != null && json['description'].contains('#')) {
      final parts = json['description'].toString().split('#');
      if (parts.length > 1) {
        orderNum = parts[1].split(' ').first;
      }
    }

    return Transaction(
      id: json['id'],
      orderNumber: orderNum,
      description: json['description'] ?? '',
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      timestamp: DateTime.tryParse(json['created_at']) ?? DateTime.now(),
      transactionType: json['transaction_type'] ?? 'debit',
      status: json['status'] ?? 'completed',
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

class _VendorWalletScreenState extends State<VendorWalletScreen> {
  Map<String, dynamic>? _walletData;
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  bool _isExporting = false;

  DateTime _startDate = DateTime(2020, 1, 1);
  DateTime _endDate = DateTime.now().add(const Duration(days: 365));
  int _currentPage = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
  }

  String _formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<void> _fetchWalletData({bool isRefresh = false}) async {
    if (isRefresh) {
      _currentPage = 1;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.token;
    if (token == null) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      final walletData = await ApiService().getVendorWallet(token);

      final transactionResponse = await ApiService().getWalletTransactions(
        token,
        page: _currentPage,
      );

      if (mounted) {
        setState(() {
          _walletData = walletData;
          final List txnList = transactionResponse['transactions'] ?? [];
          if (_currentPage == 1) {
            _transactions = txnList.map((t) => Transaction.fromJson(t)).toList();
          } else {
            _transactions.addAll(txnList.map((t) => Transaction.fromJson(t)).toList());
          }
          _totalPages = transactionResponse['total_pages'] ?? 1;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    await _fetchWalletData(isRefresh: true);
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _transactions.clear();
      });
      await _fetchWalletData(isRefresh: true);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);

    try {
      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("EzeyWay Wallet Report",
                        style: pw.TextStyle(
                            fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now())),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Period:",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          "${DateFormat('MMM d, yyyy').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_endDate)}"),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("Current Balance:",
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          "NPR ${_walletData?['balance']?.toString() ?? '0.00'}",
                          style: const pw.TextStyle(fontSize: 18)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headers: ['Date', 'Description', 'Order #', 'Type', 'Amount'],
                data: _transactions.map((txn) {
                  return [
                    DateFormat('MMM d, yyyy').format(txn.timestamp),
                    txn.description,
                    txn.orderNumber ?? 'N/A',
                    txn.transactionType.toUpperCase(),
                    "NPR ${txn.amount.abs().toStringAsFixed(2)}"
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  "Total Earned: NPR ${_walletData?['total_earned'] ?? '0.00'}",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Wallet_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("PDF Generated Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error Exporting PDF: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = _walletData?['balance']?.toString() ?? '0.00';
    final totalSpent = _walletData?['total_spent']?.toString() ?? '0.00';

    return Scaffold(
      backgroundColor: AppTheme.homeBackgroundDark,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: AppTheme.homeBackgroundDark,
          elevation: 0,
          automaticallyImplyLeading: false,
          flexibleSpace: Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10),
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                ),
                Expanded(
                  child: Text(
                    'My Wallet',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        backgroundColor: const Color(0xFF1E1E1E),
        onRefresh: _onRefresh,
        child: Stack(
          children: [
            CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Balance Card
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AppTheme.primaryColor.withOpacity(0.15),
                            AppTheme.primaryColor.withOpacity(0.05)
                          ]),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Current Balance',
                                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text('NPR $balance',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildStat('Total Spent', 'NPR $totalSpent'),
                                const Spacer(),
                                ElevatedButton.icon(
                                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Add Money feature coming soon!"))),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text("Add Money"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Date Filter Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Transaction History",
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                const SizedBox(height: 4),
                                Text(
                                  "${DateFormat('MMM d').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_endDate)}",
                                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                ),
                              ],
                            ),
                            Flexible(
                              child: Row(
                                children: [
                                  // Export PDF button with loading state
                                  GestureDetector(
                                    onTap: _isExporting ? null : _exportPdf,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2C2C2C),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _isExporting
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: AppTheme.primaryColor,
                                                  ),
                                                )
                                              : const Icon(Icons.picture_as_pdf,
                                                  size: 16, color: AppTheme.primaryColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            _isExporting ? "Export" : "PDF",
                                            style: GoogleFonts.plusJakartaSans(
                                                fontSize: 12, color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Filter button
                                  InkWell(
                                    onTap: _isLoading ? null : _selectDateRange,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2C2C2C),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.calendar_today,
                                              size: 14, color: AppTheme.primaryColor),
                                          SizedBox(width: 4),
                                          Text("Filter",
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),

                if (_isLoading && _transactions.isEmpty)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
                  )
                else if (_transactions.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: Text("No transactions in this period",
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index == _transactions.length) {
                          if (_currentPage < _totalPages) {
                            _currentPage++;
                            _fetchWalletData();
                            return const Center(
                                child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(color: AppTheme.primaryColor)));
                          }
                          return const SizedBox(height: 100);
                        }
                        final txn = _transactions[index];
                        final isCredit = txn.transactionType == 'credit';
                        return _buildTransactionCard(txn, isCredit);
                      },
                      childCount: _transactions.length + 1,
                    ),
                  ),
              ],
            ),

            // Global overlay loader for initial load
            if (_isLoading && _transactions.isNotEmpty)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey)),
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      );

  Widget _buildTransactionCard(Transaction txn, bool isCredit) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: (isCredit ? Colors.green : Colors.red).withOpacity(0.15),
                borderRadius: BorderRadius.circular(22)),
            child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                color: isCredit ? Colors.green : Colors.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(txn.description,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                    '${txn.orderNumber ?? 'N/A'} • ${DateFormat('MMM d, h:mm a').format(txn.timestamp)} • ${txn.status}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'} NPR ${txn.amount.abs().toStringAsFixed(2)}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.bold, color: isCredit ? Colors.green : Colors.red),
          ),
        ],
      ),
    );
  }
}