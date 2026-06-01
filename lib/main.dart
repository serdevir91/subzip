import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/archive_service.dart';
import 'services/notification_service.dart';
import 'providers/app_state_provider.dart';
import 'providers/file_system_provider.dart';
import 'providers/task_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  await NotificationService().init();

  // Create Services
  final storageService = StorageService();
  final archiveService = ArchiveService();

  // Initialize Storage Service (resolves directories and preferences)
  await storageService.init();

  // Create state providers
  final appState = AppStateProvider();
  final fileSystem = FileSystemProvider(storageService: storageService);
  final taskProvider = TaskProvider(
    storageService: storageService,
    archiveService: archiveService,
  );

  // Initialize providers
  await appState.init();
  await fileSystem.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: fileSystem),
        ChangeNotifierProvider.value(value: taskProvider),
      ],
      child: const SubZipApp(),
    ),
  );
}

class SubZipApp extends StatelessWidget {
  const SubZipApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final accentColor = appState.accentColor;

    return MaterialApp(
      title: 'SubZip',
      debugShowCheckedModeBanner: false,
      themeMode: appState.themeMode,
      
      // Light Theme
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.light,
          primary: accentColor,
        ),
        scaffoldBackgroundColor: const Color(0xFFF9F9F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 8,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 65,
          indicatorColor: accentColor.withOpacity(0.15),
        ),
      ),

      // Dark Theme (AMOLED Black base)
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.dark,
          primary: accentColor,
          surface: const Color(0xFF121212),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF000000), // AMOLED Pure Black
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF161616),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0A0A0A),
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 65,
          indicatorColor: accentColor.withOpacity(0.2),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
