import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LineSDK.instance
      .setup(const String.fromEnvironment('LINE_CHANNEL_ID'))
      .then((_) {
    debugPrint('LineSDK Prepared');
  });
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Auth LINE login',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        sliderTheme: SliderThemeData(
          overlayShape: SliderComponentShape.noOverlay,
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Firebase Auth x LINE ログイン'),
          elevation: 4,
          shadowColor: Theme.of(context).shadowColor,
        ),
        body: Center(
          child: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              if (user == null) {
                return const _SignedOut();
              }
              return _SignedIn(
                appUserId: FirebaseAuth.instance.currentUser!.uid,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SignedOut extends StatefulWidget {
  const _SignedOut();

  @override
  State<_SignedOut> createState() => _SignedOutState();
}

class _SignedOutState extends State<_SignedOut> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isLoading ? null : _signInWithLine,
      child: Text(
        _isLoading ? '通信中...' : 'LINE ログインする',
      ),
    );
  }

  /// LINE で Firebase Authentication にログインする。
  Future<void> _signInWithLine() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // LineSDK の login メソッドをコールする
      final loginResult =
          await LineSDK.instance.login(scopes: ['profile', 'openid', 'email']);

      // 得られる LoginResult 型の値にアクセストークン文字列が入っている。
      final accessToken =
          loginResult.accessToken.data['access_token'] as String;

      // Firebase Functions の httpsCallable を使用してバックエンドサーバと通信する。
      // リクエストボディに上で得られたアクセストークンを与える。
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast1')
          .httpsCallable('createfirebaseauthcustomtoken');
      final response = await callable.call<Map<String, dynamic>>(
        <String, dynamic>{'accessToken': accessToken},
      );

      // バックエンドサーバで作成されたカスタムトークンを得る。
      final customToken = response.data['customToken'] as String;

      // カスタムトークンを用いて Firebase Authentication にサインインする。
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
    } finally {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('サインインしました。'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.appUserId});

  final String appUserId;

  static const double _imageRadius = 64;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('appUsers')
          .doc(appUserId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox();
        }
        final documentSnapshot = snapshot.data!;
        if (!documentSnapshot.exists) {
          return const SizedBox();
        }
        final data = documentSnapshot.data();
        final name = data?['name'] as String? ?? '';
        final imageUrl = data?['imageUrl'] as String? ?? '';
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (imageUrl.isEmpty)
              const CircleAvatar(
                radius: _imageRadius,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, size: _imageRadius * 2),
              )
            else
              ClipOval(
                child: Image.network(
                  imageUrl,
                  height: _imageRadius * 2,
                  width: _imageRadius * 2,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            IconButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.exit_to_app),
            ),
          ],
        );
      },
    );
  }
}
