import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../alternatives/alternatives_screen.dart';
import '../audit/audit_screen.dart';
import '../chat/chat_screen.dart';
import '../credit/credit_screen.dart';
import '../finance/finance_screen.dart';
import '../home/home_screen.dart';
import '../inventory/inventory_screen.dart';
import '../inventory/medicine_detail_screen.dart';
import '../inventory/register_medicine_screen.dart';
import '../orders/orders_screen.dart';
import '../reports/reports_screen.dart';
import '../rxlog/rxlog_screen.dart';
import '../sales/sales_screen.dart';
import '../settings/settings_screen.dart';
import '../stocktake/stocktake_screen.dart';
import '../suppliers/suppliers_screen.dart';

/// SCREENS map of the HTML: name -> widget.
/// Names: home, inventory, sales, medicine, register, chat, reports, audit,
/// finance, suppliers, stocktake, alternatives, credit, customer, rxlog,
/// orders, settings.
Widget buildScreen(NavEntry e) {
  switch (e.name) {
    case 'home':
      return const HomeScreen();
    case 'inventory':
      return const InventoryScreen();
    case 'sales':
      return const SalesScreen();
    case 'medicine':
      return MedicineDetailScreen(medicineId: (e.params['id'] ?? '') as String);
    case 'register':
      return const RegisterMedicineScreen();
    case 'chat':
      return const ChatScreen();
    case 'reports':
      return const ReportsScreen();
    case 'audit':
      return const AuditScreen();
    case 'finance':
      return const FinanceScreen();
    case 'suppliers':
      return const SuppliersScreen();
    case 'stocktake':
      return const StocktakeScreen();
    case 'alternatives':
      return const AlternativesScreen();
    case 'credit':
    case 'customer':
      return const CreditScreen();
    case 'rxlog':
      return const RxLogScreen();
    case 'orders':
      return const OrdersScreen();
    case 'settings':
      return const SettingsScreen();
    default:
      return const HomeScreen();
  }
}
