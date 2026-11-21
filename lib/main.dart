import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'config/supabase_config.dart';
import 'config/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/cashless_controller.dart';
import 'services/cashless_service.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/transactions_screen.dart';
import 'screens/search_screen.dart';
import 'screens/kiosk_screen.dart';
import 'screens/payments_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  try {
    // Initialize Supabase
    debugPrint('Initializing Supabase...');
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    debugPrint('✓ Supabase initialized successfully');

    runApp(const MyApp());
  } catch (e, stackTrace) {
    debugPrint('✗ Fatal error during app initialization: $e');
    debugPrint('Stack trace: $stackTrace');
    runApp(const ErrorApp(error: 'Failed to initialize app'));
  }
}

class ErrorApp extends StatelessWidget {
  final String error;

  const ErrorApp({required this.error, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Container(
          color: Colors.red.shade900,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'App Initialization Error',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    error,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // Whenever the session ends (Sign out, or the account was removed and
    // the session could not be refreshed), return to the login screen.
    _authSubscription = AuthService().onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        // Also covers sessions that ended without pressing Sign out.
        CashlessService().clearSecret();
        _navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'CTU Kiosk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/main': (context) => const MainScreen(),
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // Created here (not in the tab) so the badge and new-payment alert work
  // while staff are on other tabs.
  final CashlessController _cashless = CashlessController();
  late final List<Widget> _screens = [
    const DashboardScreen(),
    PaymentsScreen(controller: _cashless),
    const TransactionsScreen(),
    const ReportsScreen(),
    const SearchScreen(),
    const KioskScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _cashless.start();
    // App reopened with a saved session: refresh the secret if online.
    CashlessService().refreshSecret();
  }

  @override
  void dispose() {
    _cashless.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: _paymentsIcon(Icons.qr_code_2_outlined),
            selectedIcon: _paymentsIcon(Icons.qr_code_2),
            label: 'Payments',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          const NavigationDestination(
            icon: Icon(Icons.summarize_outlined),
            selectedIcon: Icon(Icons.summarize),
            label: 'Reports',
          ),
          const NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Kiosk',
          ),
        ],
      ),
    );
  }

  Widget _paymentsIcon(IconData icon) {
    return ListenableBuilder(
      listenable: _cashless,
      builder: (context, _) {
        final count = _cashless.pending.length;
        return Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: Icon(icon),
        );
      },
    );
  }
}
