// lib/screens/lunch_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mcapps/services/api_client.dart';

class LunchPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const LunchPage({super.key, required this.userData});

  @override
  State<LunchPage> createState() => _LunchPageState();
}

class _LunchPageState extends State<LunchPage> {
  final ApiClient api = ApiClient();

  // UI state
  bool loading = true;
  bool submitting = false;
  bool refreshing = false;
  final Set<int> _deleting = {}; // order IDs being deleted
  final GlobalKey _ordersHeaderKey = GlobalKey();

  // Employee
  int? employeeId;
  String displayName = 'User';
  String department = 'Unknown Department';
  String? username;
  String? email;

  // Active window (from API)
  String? activeDate;           // 'YYYY-MM-DD'
  String? activeWindowLabel;    // '8:00 AM–4:00 PM'
  DateTime? _winStart;          // parsed start datetime (local)
  DateTime? _winEnd;            // parsed end datetime (local)
  Timer? _ticker;               // to refresh OPEN/CLOSED + delete visibility

  // Dropdown data
  final Map<int, String> suppliers = {};            // supplierId -> supplierName
  final Map<int, List<_Item>> itemsBySupplier = {}; // supplierId -> [_Item]
  int? selectedSupplierId;
  int? selectedItemId;

  // Orders (keep all; show latest grouped by date)
  List<OrderItem> _allOrders = [];

  @override
  void initState() {
    super.initState();
    _hydrateUser();
    _boot();
    // Periodic UI refresh so "OPEN/CLOSED" and delete visibility update live
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _hydrateUser() {
    displayName =
        widget.userData['displayname']?.toString() ??
        widget.userData['display_name']?.toString() ??
        'User';
    department = widget.userData['department']?.toString() ?? 'Unknown Department';
    username = widget.userData['username']?.toString() ??
        widget.userData['userPrincipalName']?.toString().split('@').first;
    email = widget.userData['mail']?.toString() ??
        widget.userData['email']?.toString() ??
        widget.userData['userPrincipalName']?.toString();
  }

  Future<void> _boot() async {
    try {
      // 1) Verify employee
      if (username == null || email == null) {
        throw ApiException('Missing username/email for verification.', code: 'MISSING_PARAMETER');
      }

      Employee emp;
      try {
        emp = await api.verifyEmployee(username: username!, email: email!);
      } on ApiException catch (e) {
        // If not registered, block and exit to Home
        if ((e.code ?? '').toUpperCase() == 'EMPLOYEE_NOT_FOUND' ||
            e.message.toLowerCase().contains('employee not found')) {
          await _showAccessRestrictedAndExit();
          return;
        }
        rethrow;
      }

      employeeId = emp.id;
      displayName = emp.displayName.isNotEmpty ? emp.displayName : displayName;
      department = emp.department.isNotEmpty ? emp.department : department;

      // 2) Server ACTIVE DATE + TIME WINDOW
      await _loadActiveWindow();

      // 3) Dropdowns
      final links = await api.getDropdownItems();
      _indexDropdowns(links);

      // 4) Load all orders (sorted latest first)
      await _loadOrders();
    } catch (e) {
      _showSnack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Calls API that returns:
  /// {
  ///   "status":"success",
  ///   "data":{
  ///     "active_date":"YYYY-MM-DD",
  ///     "active_start_datetime":"YYYY-MM-DD HH:MM:SS",
  ///     "active_end_datetime":"YYYY-MM-DD HH:MM:SS"
  ///   }
  /// }
  Future<void> _loadActiveWindow() async {
    final win = await api.getActiveWindow(); // <-- must exist in ApiClient
    final data = (win['data'] as Map<String, dynamic>);
    final dateYmd  = data['active_date']?.toString();
    final startRaw = data['active_start_datetime']?.toString();
    final endRaw   = data['active_end_datetime']?.toString();

    if (dateYmd == null || dateYmd.isEmpty) {
      throw ApiException('Active date not available from server.');
    }

    activeDate = dateYmd;
    if (startRaw != null && endRaw != null && startRaw.isNotEmpty && endRaw.isNotEmpty) {
      _winStart = _parseLocal(startRaw);
      _winEnd   = _parseLocal(endRaw);
      activeWindowLabel = _formatWindowLabel(_winStart!, _winEnd!, use12h: true);
    } else {
      _winStart = null;
      _winEnd = null;
      activeWindowLabel = null;
    }
    if (mounted) setState(() {});
  }

  DateTime _parseLocal(String raw) => DateTime.parse(raw.replaceFirst(' ', 'T'));
  String _formatWindowLabel(DateTime s, DateTime e, {bool use12h = true}) {
    final fmt = use12h ? DateFormat('h:mm a') : DateFormat('HH:mm');
    return '${fmt.format(s)}–${fmt.format(e)}';
  }

  bool get _isWindowOpen {
    if (_winStart == null || _winEnd == null) return false;
    final now = DateTime.now();
    return now.isAfter(_winStart!) && now.isBefore(_winEnd!);
  }

  String _windowBadgeText() {
    // Hide badge when window data is missing (no "UNKNOWN")
    if (_winStart == null || _winEnd == null) return '';
    final now = DateTime.now();
    if (now.isBefore(_winStart!)) {
      final d = _winStart!.difference(now);
      return 'OPENS IN ${_fmtDurationShort(d)}';
    } else if (now.isAfter(_winEnd!)) {
      return 'CLOSED';
    } else {
      final d = _winEnd!.difference(now);
      return 'OPEN • ENDS IN ${_fmtDurationShort(d)}';
    }
  }

  String _fmtDurationShort(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  void _indexDropdowns(List<DropdownLink> links) {
    suppliers.clear();
    itemsBySupplier.clear();

    for (final l in links) {
      suppliers[l.supplierId] = l.supplierName;
    }

    final sorted = suppliers.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final entry in sorted) {
      final sid = entry.key;
      itemsBySupplier[sid] = links
          .where((l) => l.supplierId == sid)
          .map((l) => _Item(itemId: l.itemId, name: l.itemName))
          .toSet()
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }
  }

  Future<void> _loadOrders() async {
    if (employeeId == null) return;
    setState(() => refreshing = true);
    try {
      final all = await api.getOrdersByEmployee(employeeId!);
      all.sort((a, b) {
        final d1 = DateTime.tryParse(a.date) ?? DateTime(1970);
        final d2 = DateTime.tryParse(b.date) ?? DateTime(1970);
        final cmp = d2.compareTo(d1);
        if (cmp != 0) return cmp;
        return b.id.compareTo(a.id);
      });
      _allOrders = all;
      if (mounted) setState(() {});
    } catch (e) {
      _showSnack('Could not load orders: $e', error: true);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  // After add, re-fetch a couple times (in case GET lags), then scroll to list
  Future<void> _loadOrdersEnsureVisible(int createdId) async {
    for (int i = 0; i < 3; i++) {
      await _loadOrders();
      if (_allOrders.any((o) => o.id == createdId)) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (_ordersHeaderKey.currentContext != null) {
      await Future.delayed(const Duration(milliseconds: 50));
      Scrollable.ensureVisible(
        _ordersHeaderKey.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _submit() async {
    if (employeeId == null) {
      _showSnack('Employee not verified.', error: true);
      return;
    }
    if (activeDate == null) {
      _showSnack('Active date unavailable. Try again.', error: true);
      return;
    }
    if (selectedSupplierId == null || selectedItemId == null) {
      _showSnack('Please select both supplier and meal type.', error: true);
      return;
    }

    setState(() => submitting = true);
    try {
      final id = await api.addOrder(
        employeeId: employeeId!,
        supplierId: selectedSupplierId!,
        itemId: selectedItemId!,
      );

      // Optimistic insert (immediate feedback)
      final supplierName = suppliers[selectedSupplierId!] ?? 'Supplier';
      final itemName = (itemsBySupplier[selectedSupplierId!] ?? [])
              .firstWhere((it) => it.itemId == selectedItemId!,
                  orElse: () => _Item(itemId: selectedItemId!, name: 'Item'))
              .name;

      setState(() {
        _allOrders.insert(
          0,
          OrderItem(
            id: id,
            date: activeDate!, // server active date; will be exact after reload
            quantity: 1,
            status: 1,
            employeeName: displayName,
            supplierName: supplierName,
            itemName: itemName,
          ),
        );
        selectedItemId = null; // keep supplier for quick repeat
      });

      _showSnack('🍱 Order #$id placed for ${activeDate!}');
      await _loadOrdersEnsureVisible(id);
    } catch (e) {
      _showSnack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _deleteOrder(int orderId) async {
    if (_deleting.contains(orderId)) return;
    setState(() => _deleting.add(orderId));
    try {
      await api.cancelOrder(orderId);
      setState(() => _allOrders.removeWhere((o) => o.id == orderId));
      _showSnack('Order #$orderId deleted.');
    } catch (e) {
      _showSnack('Delete failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _deleting.remove(orderId));
    }
  }

  // ===== Access control =====
  Future<void> _showAccessRestrictedAndExit() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NiceDialog(
        icon: Icons.lock_person_rounded,
        iconColor: Colors.amberAccent,
        title: 'Access Restricted',
        message:
            'You are not registered for Lunch Ordering.\nPlease contact the Admin Department to request access.',
        primaryText: 'OK',
        onPrimary: () => Navigator.pop(context, true),
      ),
    );
    _exitToHome();
  }

  void _exitToHome() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _confirmDelete(int orderId, String title) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NiceDialog(
        icon: Icons.delete_forever_rounded,
        iconColor: Colors.redAccent,
        title: 'Delete this order?',
        message: title,
        primaryText: 'Delete',
        primaryColor: Colors.redAccent,
        onPrimary: () {
          Navigator.pop(context);
          _deleteOrder(orderId);
        },
        secondaryText: 'Cancel',
        onSecondary: () => Navigator.pop(context),
      ),
    );
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : Colors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color kBg = Color(0xFF1E3C72);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Lunch',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      ),
      body: SafeArea(
        child: loading
            ? const _PageLoader()
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadActiveWindow();
                  await _loadOrders();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heroHeader(), // shows date + time window from server
                      const SizedBox(height: 16),
                      _userCard(),
                      const SizedBox(height: 18),
                      _supplierDropdown(),   // capped height so it won’t fill screen
                      const SizedBox(height: 14),
                      _itemPickerField(),    // NEW: bottom-sheet searchable picker
                      const SizedBox(height: 22),
                      ElevatedButton.icon(
                        onPressed: submitting ? null : _submit,
                        icon: const Icon(Icons.send),
                        label: submitting
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : const Text('Submit Lunch'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.white,
                          elevation: 6,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 26),
                      KeyedSubtree(key: _ordersHeaderKey, child: _ordersHeader()),
                      const SizedBox(height: 8),
                      if (refreshing) const _SectionLoader(),
                      if (!refreshing && _allOrders.isEmpty) _emptyOrders(),
                      if (!refreshing && _allOrders.isNotEmpty) _ordersListGroupedByDate(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ===== Header & cards =====
  Widget _heroHeader() {
    // Show server date & time window, e.g. "2025-09-11 • 8:00 AM–4:00 PM"
    final dateText = activeDate ?? '—';
    final windowText = activeWindowLabel ?? '—';
    final badgeText = _windowBadgeText();
    final isOpen = _isWindowOpen;

    return Container(
      decoration: _glass(),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E6AD6), Color(0xFF5BC0EB)],
              ),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 3))],
            ),
            padding: const EdgeInsets.all(12),
            child: const Icon(Icons.restaurant_menu, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🍽️ Lunch Ordering',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                // Date row
                Row(
                  children: [
                    const Icon(Icons.event, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dateText, // YYYY-MM-DD
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Window row
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        windowText, // 8:00 AM–4:00 PM
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Badge — ONLY when we have a non-empty text (no "UNKNOWN")
                if (badgeText.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOpen ? Colors.greenAccent.withOpacity(.2) : Colors.white12,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: isOpen ? Colors.greenAccent : Colors.white30),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: isOpen ? Colors.greenAccent : Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: .3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ordersHeader() => Row(
        children: const [
          Expanded(
            child: Text(
              'Latest Orders',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );

  // Build orders grouped by date (desc)
  Widget _ordersListGroupedByDate() {
    final Map<String, List<OrderItem>> grouped = {};
    for (final o in _allOrders) {
      (grouped[o.date] ??= []).add(o);
    }
    final keys = grouped.keys.toList()
      ..sort((a, b) {
        final d1 = DateTime.tryParse(a) ?? DateTime(1970);
        final d2 = DateTime.tryParse(b) ?? DateTime(1970);
        return d2.compareTo(d1); // newest first
      });

    final widgets = <Widget>[];
    for (final ymd in keys) {
      widgets.add(_dateSectionHeader(ymd));
      final items = grouped[ymd]!..sort((a, b) => b.id.compareTo(a.id));
      widgets.addAll(items.map(_orderTile));
      widgets.add(const SizedBox(height: 6));
    }
    return Column(children: widgets);
  }

  Widget _dateSectionHeader(String ymd) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                const Icon(Icons.today, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  ymd, // exact YYYY-MM-DD
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _canDeleteOrderNow(OrderItem o) {
    if (o.status != 1) return false;
    if (activeDate == null || _winStart == null || _winEnd == null) return false;
    if (o.date != activeDate) return false;
    final now = DateTime.now();
    return now.isAfter(_winStart!) && now.isBefore(_winEnd!);
  }

  Widget _orderTile(OrderItem o) {
    final isDeleting = _deleting.contains(o.id);
    final showDelete = _canDeleteOrderNow(o);
    final titleText = '${o.supplierName} • ${o.itemName}';

    final subPieces = <String>[
      'ID #${o.id}',
      o.date,
      if (o.date == activeDate && activeWindowLabel != null) activeWindowLabel!,
    ];
    final subtitleText = subPieces.join('  •  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _glass(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          titleText,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitleText, style: const TextStyle(color: Colors.white70)),
        trailing: (o.status != 1)
            ? const Chip(
                label: Text('Cancelled', style: TextStyle(color: Colors.white)),
                backgroundColor: Colors.redAccent,
              )
            : (showDelete
                ? (isDeleting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    : TextButton.icon(
                        onPressed: () => _confirmDelete(o.id, titleText),
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      ))
                : null),
      ),
    );
  }

  Widget _emptyOrders() => Container(
        padding: const EdgeInsets.all(18),
        decoration: _glass(),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white70),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No orders yet.',
                maxLines: 2,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      );

  // === Form pieces ===
  Widget _userCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: _glass(),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.apartment, color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Flexible(child: Text(department, style: const TextStyle(color: Colors.white70))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  static const Color _menuBg = Color(0xFF0F2040); // opaque dark navy
  static const TextStyle _menuTextStyle = TextStyle(color: Colors.white);

  // -------- Supplier: still a dropdown, but with capped height --------
  Widget _supplierDropdown() {
    final items = suppliers.entries
        .map((e) => DropdownMenuItem<int>(
              value: e.key,
              child: Text(e.value, style: _menuTextStyle),
            ))
        .toList();

    return _dropdownCard(
      title: 'Select Supplier',
      icon: Icons.storefront,
      child: DropdownButtonFormField<int>(
        dropdownColor: _menuBg,
        initialValue: selectedSupplierId,
        iconEnabledColor: Colors.white,
        decoration: _fieldDecoration(icon: Icons.storefront),
        style: const TextStyle(color: Colors.white),
        items: items,
        menuMaxHeight: 320, // ⬅️ prevents full-screen dropdown
        onChanged: (val) {
          setState(() {
            selectedSupplierId = val;
            selectedItemId = null;
          });
        },
      ),
    );
  }

  // -------- Meal: REPLACED with bottom-sheet searchable picker --------
  Widget _itemPickerField() {
    final hasSupplier = selectedSupplierId != null;
    final selectedText = () {
      if (!hasSupplier || selectedItemId == null) return 'Choose a meal';
      final list = itemsBySupplier[selectedSupplierId] ?? [];
      final it = list.firstWhere(
        (x) => x.itemId == selectedItemId,
        orElse: () => _Item(itemId: selectedItemId!, name: 'Item'),
      );
      return it.name;
    }();

    return _dropdownCard(
      title: 'Select Meal',
      icon: Icons.fastfood,
      child: InkWell(
        onTap: !hasSupplier
            ? null
            : () async {
                final picked = await _showMealPickerBottomSheet(
                  context,
                  selectedSupplierId!,
                  itemsBySupplier[selectedSupplierId!] ?? [],
                );
                if (picked != null) {
                  HapticFeedback.selectionClick();
                  setState(() => selectedItemId = picked.itemId);
                }
              },
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          isFocused: false,
          isEmpty: false,
          decoration: _fieldDecoration(icon: Icons.fastfood),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasSupplier ? selectedText : 'Select a supplier first',
                  style: TextStyle(
                    color: hasSupplier ? Colors.white : Colors.white54,
                    fontWeight: hasSupplier ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_up, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  // === Shared UI helpers ===
  Widget _dropdownCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  BoxDecoration _glass() => BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      );

  InputDecoration _fieldDecoration({required IconData icon}) => InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.14),
        hintStyle: const TextStyle(color: Colors.white70),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 1.2),
        ),
      );

  // ---------------- Bottom Sheet Meal Picker ----------------
  Future<_Item?> _showMealPickerBottomSheet(
    BuildContext context,
    int supplierId,
    List<_Item> allItems,
  ) async {
    // Build quick picks (recent for this supplier; fallback alpha)
    final recent = _recentItemsForSupplier(supplierId, allItems, max: 6);

    return showModalBottomSheet<_Item>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F2040),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return _MealPickerSheet(
          title: suppliers[supplierId] ?? 'Meals',
          items: allItems,
          quickPicks: recent,
        );
      },
    );
  }

  List<_Item> _recentItemsForSupplier(int supplierId, List<_Item> all, {int max = 6}) {
    // Heuristic: use existing orders with same supplier name (API list view lacks item_id)
    final seen = <int>{};
    final recents = <_Item>[];

    final supplierName = suppliers[supplierId] ?? '';
    for (final o in _allOrders) {
      if (o.supplierName == supplierName) {
        final match = all.firstWhere(
          (it) => it.name == o.itemName,
          orElse: () => _Item(itemId: -1, name: ''),
        );
        if (match.itemId != -1 && !seen.contains(match.itemId)) {
          recents.add(match);
          seen.add(match.itemId);
          if (recents.length >= max) break;
        }
      }
    }

    if (recents.isEmpty) {
      // Fallback: first N alphabetically
      final copy = [...all]..sort((a, b) => a.name.compareTo(b.name));
      return copy.take(max).toList();
    }
    return recents;
  }
}

// ===== Loaders =====
class _PageLoader extends StatelessWidget {
  const _PageLoader();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 80),
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
}

class _SectionLoader extends StatelessWidget {
  const _SectionLoader();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
}

// ===== Simple item model =====
class _Item {
  final int itemId;
  final String name;
  _Item({required this.itemId, required this.name});
  @override
  bool operator ==(Object other) => other is _Item && other.itemId == itemId;
  @override
  int get hashCode => itemId.hashCode;
}

// ===== Nice reusable dialog =====
class _NiceDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String primaryText;
  final VoidCallback onPrimary;
  final String? secondaryText;
  final VoidCallback? onSecondary;
  final Color? primaryColor;

  const _NiceDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.primaryText,
    required this.onPrimary,
    this.secondaryText,
    this.onSecondary,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    const Color kBg = Color(0xFF1E3C72);
    return Dialog(
      backgroundColor: kBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: iconColor.withOpacity(0.18),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.3),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (secondaryText != null && onSecondary != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondary,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(secondaryText!),
                    ),
                  ),
                if (secondaryText != null && onSecondary != null)
                  const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor ?? Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(primaryText),
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

// ===== Bottom Sheet UI =====
class _MealPickerSheet extends StatefulWidget {
  final String title;
  final List<_Item> items;
  final List<_Item> quickPicks;

  const _MealPickerSheet({
    required this.title,
    required this.items,
    required this.quickPicks,
  });

  @override
  State<_MealPickerSheet> createState() => _MealPickerSheetState();
}

class _MealPickerSheetState extends State<_MealPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _q = _searchCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.items
        : widget.items
            .where((it) => it.name.toLowerCase().contains(_q.toLowerCase()))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  hintText: 'Search meals...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Quick picks
              if (_q.isEmpty && widget.quickPicks.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.quickPicks.map((it) {
                      return ActionChip(
                        label: Text(it.name, style: const TextStyle(color: Colors.white)),
                        backgroundColor: Colors.white.withOpacity(0.08),
                        side: const BorderSide(color: Colors.white24),
                        onPressed: () => Navigator.pop<_Item>(context, it),
                      );
                    }).toList(),
                  ),
                ),
              if (_q.isEmpty && widget.quickPicks.isNotEmpty) const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (_, i) {
                    final it = filtered[i];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      title: Text(
                        it.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      onTap: () => Navigator.pop<_Item>(context, it),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
