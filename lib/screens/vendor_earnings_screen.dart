// lib/screens/vendor_earnings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/data_preloader_service.dart';
import '../services/auth_service.dart';
import '../config.dart' as appConfig;

class SalesTransaction {
  final String id;
  final String orderNumber;
  final String customerName;
  final double amount;
  final String type; // 'sale' or 'refund'
  final String status;
  final DateTime createdAt;
  final int itemsCount;

  SalesTransaction({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.amount,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.itemsCount,
  });
}

class VendorEarningsScreen extends StatefulWidget {
  const VendorEarningsScreen({super.key});

  @override
  State<VendorEarningsScreen> createState() => _VendorEarningsScreenState();
}

class _VendorEarningsScreenState extends State<VendorEarningsScreen> with TickerProviderStateMixin {
  String selectedPeriod = 'all';
  String activeTab = 'all';
  List<SalesTransaction> transactions = [];
  bool isLoading = true;
  
  // Stats
  double totalSales = 0.0;
  double totalRefunds = 0.0;
  double netEarnings = 0.0;
  double todaySales = 0.0;
  double monthSales = 0.0;
  
  // Filter
  String? dateFrom;
  String? dateTo;
  bool showDateFilter = false;
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEarningsData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEarningsData() async {
    // First, try to load from cache instantly
    final preloader = Provider.of<DataPreloaderService>(context, listen: false);
    final cachedEarnings = preloader.vendorEarnings;
    final cachedTransactions = preloader.vendorTransactions;
    
    if (cachedEarnings != null && cachedTransactions != null) {
      // Load from cache instantly
      _processTransactionsData(cachedTransactions, fromCache: true);
      setState(() => isLoading = false);
      
      // Then refresh in background
      _refreshDataInBackground();
      return;
    }
    
    // If no cache, load normally
    setState(() => isLoading = true);
    await _fetchFreshData();
  }
  
  Future<void> _refreshDataInBackground() async {
    try {
      await _fetchFreshData(showLoading: false);
    } catch (e) {
      debugPrint('Background refresh failed: $e');
    }
  }

  Future<void> _fetchFreshData({bool showLoading = true}) async {
    if (showLoading) setState(() => isLoading = true);
    
    try {
      final token = Provider.of<AuthService>(context, listen: false).token;
      if (token == null) return;

      final params = <String, String>{};
      if (dateFrom != null) params['date_from'] = dateFrom!;
      if (dateTo != null) params['date_to'] = dateTo!;
      
      final uri = Uri.parse('${appConfig.Config.baseUrl}/vendor/orders/').replace(queryParameters: params);
      final response = await http.get(uri, headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List orders = [];
        
        if (data is Map<String, dynamic>) {
          orders = data['results'] ?? data['data'] ?? [];
        } else if (data is List) {
          orders = data;
        }

        _processTransactionsData(orders.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Error loading earnings: $e');
    } finally {
      if (showLoading) setState(() => isLoading = false);
    }
  }
  
  void _processTransactionsData(List<Map<String, dynamic>> orders, {bool fromCache = false}) {
    final salesTransactions = <SalesTransaction>[];
    
    // Process orders into transactions
    for (var order in orders) {
      // Add sale transaction for confirmed and delivered orders
      if (order['status'] == 'confirmed' || order['status'] == 'delivered') {
        salesTransactions.add(SalesTransaction(
          id: order['id'].toString(),
          orderNumber: order['order_number'] ?? 'N/A',
          customerName: order['customer_details']?['username'] ?? order['delivery_name'] ?? 'Unknown',
          amount: double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0.0,
          type: 'sale',
          status: order['status'] == 'delivered' ? 'completed' : 'confirmed',
          createdAt: DateTime.tryParse(order['confirmed_at'] ?? order['created_at'] ?? '') ?? DateTime.now(),
          itemsCount: (order['items'] as List?)?.length ?? 0,
        ));
      }
      
      // Add refund transactions if any
      if (order['refunds'] != null && order['refunds'] is List) {
        for (var refund in order['refunds']) {
          if (refund['status'] == 'completed') {
            salesTransactions.add(SalesTransaction(
              id: 'refund-${refund['id']}',
              orderNumber: order['order_number'] ?? 'N/A',
              customerName: order['customer_details']?['username'] ?? order['delivery_name'] ?? 'Unknown',
              amount: -(double.tryParse(refund['approved_amount']?.toString() ?? refund['requested_amount']?.toString() ?? '0') ?? 0.0),
              type: 'refund',
              status: 'completed',
              createdAt: DateTime.tryParse(refund['completed_at'] ?? refund['created_at'] ?? '') ?? DateTime.now(),
              itemsCount: (order['items'] as List?)?.length ?? 0,
            ));
          }
        }
      }
    }
    
    // Sort by date (newest first)
    salesTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Calculate stats
    final sales = salesTransactions.where((t) => t.type == 'sale');
    final refunds = salesTransactions.where((t) => t.type == 'refund');
    
    final totalSalesAmount = sales.fold(0.0, (sum, t) => sum + t.amount);
    final totalRefundsAmount = refunds.fold(0.0, (sum, t) => sum + t.amount.abs());
    
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    
    final todaySalesAmount = sales
        .where((t) => t.createdAt.isAfter(todayStart) && t.createdAt.isBefore(todayEnd))
        .fold(0.0, (sum, t) => sum + t.amount);
        
    final monthStart = DateTime(today.year, today.month, 1);
    final monthSalesAmount = sales
        .where((t) => t.createdAt.isAfter(monthStart))
        .fold(0.0, (sum, t) => sum + t.amount);
    
    setState(() {
      transactions = salesTransactions;
      totalSales = totalSalesAmount;
      totalRefunds = totalRefundsAmount;
      netEarnings = totalSalesAmount - totalRefundsAmount;
      todaySales = todaySalesAmount;
      monthSales = monthSalesAmount;
    });
  }

  List<SalesTransaction> get filteredTransactions {
    switch (activeTab) {
      case 'sales':
        return transactions.where((t) => t.type == 'sale').toList();
      case 'refunds':
        return transactions.where((t) => t.type == 'refund').toList();
      default:
        return transactions;
    }
  }

  String formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showDateFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter by Date Range', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              
              Text('From Date', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.grey[400])),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'YYYY-MM-DD',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) => dateFrom = value.isNotEmpty ? value : null,
              ),
              const SizedBox(height: 16),
              
              Text('To Date', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.grey[400])),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'YYYY-MM-DD',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) => dateTo = value.isNotEmpty ? value : null,
              ),
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _fetchFreshData();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD60A), foregroundColor: Colors.black),
                      child: const Text('Apply Filter'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          dateFrom = null;
                          dateTo = null;
                        });
                        Navigator.pop(context);
                        _fetchFreshData();
                      },
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey)),
                      child: const Text('Clear', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Text('Sales & Earnings', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _showDateFilter,
            icon: const Icon(Icons.filter_list, color: Colors.white),
          ),
          IconButton(
            onPressed: _loadEarningsData,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD60A)))
          : RefreshIndicator(
              color: const Color(0xFFFFD60A),
              backgroundColor: const Color(0xFF1E1E1E),
              onRefresh: () => _fetchFreshData(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Cards
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              children: [
                                const Icon(Icons.trending_up, color: Colors.green, size: 24),
                                const SizedBox(height: 8),
                                Text('Total Sales', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                                Text('NPR ${totalSales.toInt()}', style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              children: [
                                const Icon(Icons.trending_down, color: Colors.red, size: 24),
                                const SizedBox(height: 8),
                                Text('Total Refunds', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                                Text('NPR ${totalRefunds.toInt()}', style: const TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Net Earnings Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          Text('Net Earnings', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
                          const SizedBox(height: 12),
                          Text('NPR ${netEarnings.toInt()}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Text('Today', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                                  Text('NPR ${todaySales.toInt()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Column(
                                children: [
                                  Text('This Month', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                                  Text('NPR ${monthSales.toInt()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Transactions Section
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          // Header
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Transactions', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                Text('${transactions.length} total', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                              ],
                            ),
                          ),
                          
                          // Tabs
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: TabBar(
                              controller: _tabController,
                              labelColor: const Color(0xFFFFD60A),
                              unselectedLabelColor: Colors.grey,
                              indicatorColor: const Color(0xFFFFD60A),
                              onTap: (index) {
                                setState(() {
                                  activeTab = ['all', 'sales', 'refunds'][index];
                                });
                              },
                              tabs: [
                                Tab(text: 'All (${transactions.length})'),
                                Tab(text: 'Sales (${transactions.where((t) => t.type == 'sale').length})'),
                                Tab(text: 'Refunds (${transactions.where((t) => t.type == 'refund').length})'),
                              ],
                            ),
                          ),
                          
                          // Transaction List
                          SizedBox(
                            height: 400,
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildTransactionList(transactions),
                                _buildTransactionList(transactions.where((t) => t.type == 'sale').toList()),
                                _buildTransactionList(transactions.where((t) => t.type == 'refund').toList()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTransactionList(List<SalesTransaction> transactionList) {
    if (transactionList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('No transactions found', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transactionList.length,
      itemBuilder: (context, index) {
        final transaction = transactionList[index];
        final isRefund = transaction.type == 'refund';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isRefund ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isRefund ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isRefund ? Colors.red : Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isRefund ? 'Refund' : 'Sale'} - ${transaction.orderNumber}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '${transaction.customerName} • ${transaction.itemsCount} items',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    Text(
                      '${formatDate(transaction.createdAt)} at ${formatTime(transaction.createdAt)}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isRefund ? '' : '+'}NPR ${transaction.amount.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      color: isRefund ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: transaction.status == 'completed' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      transaction.status,
                      style: TextStyle(
                        color: transaction.status == 'completed' ? Colors.green : Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}