// lib/services/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String base = 'https://office.mclarens.lk/api';
  final http.Client _http;
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final res = await _http.get(uri).timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$base$path');
    final res = await _http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Invalid server response (${res.statusCode}).', code: 'INVALID_JSON');
    }
    if (res.statusCode != 200 || data['status'] != 'success') {
      final msg = data['message']?.toString() ?? 'Request failed';
      final code = data['error_code']?.toString();
      throw ApiException(msg, code: code);
    }
    return data;
  }

  // 0) Active window (date + timeframe)
  // Expected response:
  // {
  //   "status": "success",
  //   "message": "...",
  //   "data": {
  //     "active_date": "YYYY-MM-DD",
  //     "active_start_datetime": "YYYY-MM-DD HH:MM:SS",
  //     "active_end_datetime":   "YYYY-MM-DD HH:MM:SS"
  //   }
  // }
  Future<Map<String, dynamic>> getActiveWindow() async {
    // Your backend updated this route to include the timeframe fields.
    final data = await _get('/dropdown/active_date');

    final d = (data['data'] as Map<String, dynamic>?);
    if (d == null ||
        d['active_date'] == null ||
        d['active_start_datetime'] == null ||
        d['active_end_datetime'] == null) {
      throw ApiException('Active window payload incomplete', code: 'INVALID_PAYLOAD');
    }
    return data; // LunchPage reads data['data'] to show date + timeframe
  }

  // 1) Dropdowns
  Future<List<DropdownLink>> getDropdownItems() async {
    final data = await _get('/dropdown/items');
    final list = (data['data'] as List).cast<Map<String, dynamic>>();
    return list.map(DropdownLink.fromJson).toList();
  }

  /// Legacy helper: Active date (server-side "today")
  /// (Kept for backward-compat; new UI uses getActiveWindow())
  Future<String?> getActiveDate() async {
    final data = await _get('/dropdown/active_date');
    return (data['data'] as Map?)?['active_date']?.toString();
  }

  // 2) Orders
  Future<List<OrderItem>> getOrdersByEmployee(int employeeId) async {
    final data =
        await _get('/orders/get_by_employee', query: {'employee_id': '$employeeId'});
    final list = (data['data'] as List).cast<Map<String, dynamic>>();
    return list.map(OrderItem.fromJson).toList();
  }

  Future<int> addOrder({
    required int employeeId,
    required int supplierId,
    required int itemId,
  }) async {
    final payload = {
      'employee_id': employeeId,
      'supplier_id': supplierId,
      'item_id': itemId,
    };
    final data = await _post('/orders/add', payload);
    return (data['data'] as Map)['id'] as int;
  }

  Future<void> cancelOrder(int orderId) async {
    await _get('/orders/cancel', query: {'order_id': '$orderId'});
  }

  // 3) Employee Verification
  Future<Employee> verifyEmployee({
    required String username,
    required String email,
  }) async {
    final data = await _post('/orders/verify_employee', {
      'username': username,
      'email': email,
    });
    return Employee.fromJson((data['data'] as Map<String, dynamic>));
  }
}

class ApiException implements Exception {
  final String message;
  final String? code; // e.g., EMPLOYEE_NOT_FOUND
  ApiException(this.message, {this.code});
  @override
  String toString() => message;
}

// ===== Models =====
class DropdownLink {
  final int linkId;
  final int supplierId;
  final String supplierName;
  final int itemId;
  final String itemName;
  DropdownLink({
    required this.linkId,
    required this.supplierId,
    required this.supplierName,
    required this.itemId,
    required this.itemName,
  });
  factory DropdownLink.fromJson(Map<String, dynamic> j) => DropdownLink(
        linkId: int.tryParse(j['link_id'].toString()) ?? 0,
        supplierId: int.tryParse(j['supplier_id'].toString()) ?? 0,
        supplierName: j['supplier_name']?.toString() ?? '',
        itemId: int.tryParse(j['item_id'].toString()) ?? 0,
        itemName: j['item_name']?.toString() ?? '',
      );
}

class OrderItem {
  final int id;
  final String date; // YYYY-MM-DD
  final int quantity;
  final int status; // 1 active, -1 cancelled
  final String employeeName;
  final String supplierName;
  final String itemName;
  OrderItem({
    required this.id,
    required this.date,
    required this.quantity,
    required this.status,
    required this.employeeName,
    required this.supplierName,
    required this.itemName,
  });
  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        id: j['id'] is int ? j['id'] : int.tryParse(j['id'].toString()) ?? 0,
        date: j['date']?.toString() ?? '',
        quantity: j['quantity'] is int
            ? j['quantity']
            : int.tryParse(j['quantity'].toString()) ?? 1,
        status: j['status'] is int
            ? j['status']
            : int.tryParse(j['status'].toString()) ?? 0,
        employeeName: j['employee_name']?.toString() ?? '',
        supplierName: j['supplier_name']?.toString() ?? '',
        itemName: j['item_name']?.toString() ?? '',
      );
}

class Employee {
  final int id;
  final String displayName;
  final String username;
  final String email;
  final String department;
  final String company;
  Employee({
    required this.id,
    required this.displayName,
    required this.username,
    required this.email,
    required this.department,
    required this.company,
  });
  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] is int ? j['id'] : int.tryParse(j['id'].toString()) ?? 0,
        displayName: j['display_name']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        department: j['department']?.toString() ?? '',
        company: j['company']?.toString() ?? '',
      );
}
