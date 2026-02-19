import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'config/app_strings.dart';
import 'data/db/app_database.dart';
import 'data/services/ad_service.dart';
import 'models/credit_provider.dart';
import 'screens/split_camera_screen.dart';

// Global navigator key for context-free navigation after Bottom Sheet closes
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  // 설정 및 문구 로드
  await Future.wait([
    AppConfig.load(),
    AppStrings.load(),
    AppDatabase.instance.init(),
  ]);

  // 광고 SDK 초기화
  debugPrint('Initializing Mobile Ads SDK...');
  await AdService.initialize();
  
  // 광고 미리 로드
  final adService = AdService();
  adService.loadRewardedAd();
  debugPrint('Rewarded ad preloading started');
  
  // 카메라 권한 요청
  debugPrint(AppStrings.instance.debugCameraPermissionRequesting);
  PermissionStatus cameraStatus = await Permission.camera.request();
  
  if (cameraStatus.isDenied) {
    debugPrint(AppStrings.instance.debugCameraPermissionDenied);
  } else if (cameraStatus.isGranted) {
    debugPrint(AppStrings.instance.debugCameraPermissionGranted);
  } else if (cameraStatus.isDenied) {
    debugPrint(AppStrings.instance.debugCameraPermissionPermanentlyDenied);
  }
  
  // 카메라 초기화
  debugPrint(AppStrings.instance.debugCameraChecking);
  cameras = await availableCameras();
  debugPrint(AppStrings.instance.debugCameraCount(cameras.length));
  
  // Credit 서비스 초기화
  debugPrint(AppStrings.instance.debugCreditInitializing);
  final creditProvider = CreditProvider();
  await creditProvider.initialize();
  
  runApp(MyApp(creditProvider: creditProvider));
}

class MyApp extends StatelessWidget {
  final CreditProvider creditProvider;

  const MyApp({
    super.key,
    required this.creditProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CreditProvider>.value(
          value: creditProvider,
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: AppStrings.instance.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: SplitCameraScreen(cameras: cameras),
      ),
    );
  }
}
