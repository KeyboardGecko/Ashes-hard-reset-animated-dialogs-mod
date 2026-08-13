// import 'package:animaker/widgets/video_player_screen.dart';
// import 'package:flutter/material.dart';
// import 'screens/home_screen.dart';

// void main() {
//   runApp(const AnimationEditorApp());
// }

// class AnimationEditorApp extends StatelessWidget {
//   const AnimationEditorApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Animation Editor',
//       theme: ThemeData.dark().copyWith(
//         scaffoldBackgroundColor: Colors.grey[900],
//         appBarTheme: const AppBarTheme(backgroundColor: Colors.black87),
//       ),
//       home: const VideoPlayerScreen(),
//       // home: const HomeScreen(),
//     );
//   }
// }

// main.dart
// import 'package:animaker/widgets/audio_player_screen.dart';
import 'package:animaker/features/audio_marks/presentation/widgets/pages/audio_marks_screen.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
// import 'package:media_kit_video/media_kit_video.dart';
// import 'widgets/video_player_screen.dart';

void main() {
  // media_kit initialization
  MediaKit.ensureInitialized();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        canvasColor: const Color(0xFF121212),

        // ВАЖНО: используем CardThemeData, не CardTheme
        cardTheme: const CardThemeData(
          surfaceTintColor: Colors.transparent,
          // при желании: elevation: 0,
        ),

        dialogTheme: const DialogThemeData(
          surfaceTintColor: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const AudioMarksScreen(),
    );
  }
}
