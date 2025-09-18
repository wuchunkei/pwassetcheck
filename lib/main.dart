import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fix Asset Check',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _rememberAccount = false;
  bool _rememberPassword = false;
  bool _loading = true;
  bool _authenticating = false;
  bool _obscurePassword = true;

  static const _kRememberAccount = 'rememberAccount';
  static const _kRememberPassword = 'rememberPassword';
  static const _kSavedUsername = 'username';
  static const _kSavedPassword = 'password';
  static const _kMongoBaseUriKey = 'mongoBaseUri';
  static const _kCandidateDbsKey = 'candidateDbs';
  static const _kSuccessfulDbsKey = 'successfulDbs';
  static const String kFixedMongoBaseUri =
      'mongodb+srv://wuchunkei:FoGGy20021109!@picturemap.ef0ym3m.mongodb.net/?retryWrites=true&w=majority&appName=PictureMap';   
  // 新增：會話時間戳記與最大時長（24 小時）
  static const String _kSessionLoginAt = 'sessionLoginAt';
  static const int _kSessionMaxAgeHours = 24;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberAcc = prefs.getBool(_kRememberAccount) ?? false;
    final rememberPwd = prefs.getBool(_kRememberPassword) ?? false;
    final savedUser = rememberAcc ? (prefs.getString(_kSavedUsername) ?? '') : '';
    final savedPwd = rememberPwd ? (prefs.getString(_kSavedPassword) ?? '') : '';

    setState(() {
      _rememberAccount = rememberAcc;
      _rememberPassword = rememberPwd;
      _usernameController.text = savedUser;
      _passwordController.text = savedPwd;
      _loading = false;
    });
  }

  Future<void> _bootstrap() async {
    await _loadPrefs();
    await _tryAutoResumeSession();
  }

  Future<void> _tryAutoResumeSession() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_kSessionLoginAt);
    if (ts == null) return;
    final loginAt = DateTime.tryParse(ts);
    if (loginAt == null) return;

    final now = DateTime.now().toUtc();
    if (now.difference(loginAt.toUtc()) > const Duration(hours: _kSessionMaxAgeHours)) return;

    final available = prefs.getStringList(_kSuccessfulDbsKey) ?? <String>[];
    if (available.isEmpty) return;
    final preferred = prefs.getString('preferredDb');
    final initSel = (preferred != null && available.contains(preferred)) ? preferred : available.first;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(
          availableDatabases: available,
          initialSelection: initSel,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _persistRememberInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberAccount, _rememberAccount);
    await prefs.setBool(_kRememberPassword, _rememberPassword);
    if (_rememberAccount) {
      await prefs.setString(_kSavedUsername, _usernameController.text);
    } else {
      await prefs.remove(_kSavedUsername);
    }
    if (_rememberPassword) {
      await prefs.setString(_kSavedPassword, _passwordController.text);
    } else {
      await prefs.remove(_kSavedPassword);
    }
  }

  Future<Map<String, dynamic>?> _promptForMongoSettingsIfMissing() async {
    final prefs = await SharedPreferences.getInstance();
    String baseUri = prefs.getString(_kMongoBaseUriKey) ?? '';
    List<String> candidate = prefs.getStringList(_kCandidateDbsKey) ?? [];

    if (baseUri.isNotEmpty && candidate.isNotEmpty) return {
      'baseUri': baseUri,
      'candidate': candidate,
    };

    final baseCtrl = TextEditingController(text: baseUri);
    final dbsCtrl = TextEditingController(text: candidate.join(","));

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('MongoDB Settings Required'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Connection string (without credentials preferred):',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: baseCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. mongodb+srv://cluster-hostname/?retryWrites=true&w=majority',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Candidate database names (comma-separated):',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: dbsCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. db1,db2,db3',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final uri = baseCtrl.text.trim();
                final dbs = dbsCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                if (uri.isEmpty || dbs.isEmpty) return;
                await prefs.setString(_kMongoBaseUriKey, uri);
                await prefs.setStringList(_kCandidateDbsKey, dbs);
                if (!context.mounted) return;
                Navigator.of(ctx).pop({'baseUri': uri, 'candidate': dbs});
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    return result;
  }

  String _buildMongoUri({required String baseUri, String? username, String? password, required String dbName}) {
    final qIndex = baseUri.indexOf('?');
    final hasQuery = qIndex != -1;
    final prefix = hasQuery ? baseUri.substring(0, qIndex) : baseUri;
    final query = hasQuery ? baseUri.substring(qIndex) : '';

    const schemeSep = '://';
    final schemeIdx = prefix.indexOf(schemeSep);
    if (schemeIdx == -1) return baseUri;
    final scheme = prefix.substring(0, schemeIdx + schemeSep.length);
    final rest = prefix.substring(schemeIdx + schemeSep.length);
    String hostAndPath;
    final atIdx = rest.indexOf('@');
    if (atIdx != -1) {
      hostAndPath = rest.substring(atIdx + 1);
    } else {
      hostAndPath = rest;
    }
    if (hostAndPath.startsWith('/')) {
      hostAndPath = hostAndPath.substring(1);
    }

    final cred = (username != null && username.isNotEmpty)
        ? (password != null ? '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}@' : '${Uri.encodeComponent(username)}@')
        : '';

    final rebuilt = StringBuffer()
      ..write(scheme)
      ..write(cred)
      ..write(hostAndPath)
      ..write('/')
      ..write(dbName)
      ..write(query);

    return rebuilt.toString();
  }

  // 直接在完整連線字串中附加資料庫名稱（不解析、不移除帳密）
  String _appendDbToMongoUri(String fullBaseUri, String dbName) {
    final qIndex = fullBaseUri.indexOf('?');
    final base = qIndex == -1 ? fullBaseUri : fullBaseUri.substring(0, qIndex);
    final query = qIndex == -1 ? '' : fullBaseUri.substring(qIndex);
    final baseNoSlash = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$baseNoSlash/$dbName$query';
  }

  // 預設欲檢查的資料庫清單（根據你的需求）
  List<String> _defaultDbCandidates() => const <String>['pwhkasset', 'pwcnasset', 'pwtestasset'];

  // 確保 users 集合存在預設管理者帳號（若不存在才建立）
  Future<void> _ensureDefaultUser(mongo.Db db) async {
    final users = db.collection('users');
    try {
      // read-only: skip index creation and default user bootstrap
    } catch (_) {
      // 忽略，避免因權限或 schema 差異導致整體失敗
    }
  }

Future<void> _onLogin() async {
  if (_authenticating) return;

  setState(() {
    _authenticating = true;
  });

  try {
    await _persistRememberInfo();

    // 讀取使用者輸入的帳密
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入帳號與密碼。')),
      );
      setState(() => _authenticating = false);
      return;
    }

    // Web 端無法直接建立到 MongoDB 的 Socket 連線，直接提示並返回
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前為 Web 構建，瀏覽器無法直接連線 MongoDB。請改用 Windows/Android/iOS 構建，或在後端提供 API 作為代理。')),
      );
      setState(() => _authenticating = false);
      return;
    }

    // 固定集群連線字串
    const String baseUri = kFixedMongoBaseUri;

    // 先用快取成功過的 DB 排序，未命中則使用預設候選
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList(_kSuccessfulDbsKey) ?? <String>[];
    final candidates = _defaultDbCandidates();
    final ordered = <String>[
      ...cached.where((db) => candidates.contains(db)),
      ...candidates.where((db) => !cached.contains(db)),
    ];

    final List<String> matchedDbs = [];
    final List<String> errors = [];
    DateTime? lastLoginToShow; // 用於顯示上次登入時間（以第一個匹配到的 DB 為準）

    for (final dbName in ordered) {
      final uri = _appendDbToMongoUri(baseUri, dbName);
      mongo.Db? db;
      try {
        // 使用 Db.create 以支援 mongodb+srv 的 SRV 解析
        db = await mongo.Db.create(uri);
        await db.open().timeout(const Duration(seconds: 6));

        // 確保預設帳號存在
        // read-only: skip default user bootstrap
        // await _ensureDefaultUser(db);

        final users = db.collection('users');
        final userDoc = await users.findOne({'username': username}).timeout(const Duration(seconds: 3));
        if (userDoc != null && (userDoc['password']?.toString() ?? '') == password) {
          // 記錄此庫成功
          matchedDbs.add(dbName);

          // 取出上次登入時間（第一個匹配成功的庫作為顯示依據）
          if (lastLoginToShow == null) {
            final prev = userDoc['last_login'];
            if (prev is String) {
              try { lastLoginToShow = DateTime.tryParse(prev); } catch (_) {}
            } else if (prev is DateTime) {
              lastLoginToShow = prev.toUtc();
            }
          }

          // read-only: skip updating last_login
        }
        // 更新 last_login 的寫入邏輯已移除，保持純讀取
      } catch (e) {
        // 記錄錯誤以便提示
        debugPrint('Mongo login error on $dbName: $e');
        errors.add('$dbName: $e');
      } finally {
        try { await db?.close(); } catch (_) {}
      }
    }

    if (matchedDbs.isEmpty) {
      if (!mounted) return;
      final String msg = errors.isNotEmpty
          ? '登入失敗：無法連線或查詢（例如：${errors.first}）。請確認網路、白名單與帳密。'
          : '登入失敗：未在任何資料庫找到相符的帳密。';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      setState(() => _authenticating = false);
      return;
    }

    // 更新快取成功的資料庫清單
    await prefs.setStringList(_kSuccessfulDbsKey, matchedDbs);
    // 記錄本地會話啟動時間（UTC），供 24 小時內自動登入與到期自動登出
    await prefs.setString(_kSessionLoginAt, DateTime.now().toUtc().toIso8601String());

    // 顯示上次登入時間資訊（若有）
    if (!mounted) return;
    if (lastLoginToShow != null) {
      final local = lastLoginToShow!.toLocal();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上次登錄時間：$local')),
      );
    }

    // 進入首頁，以第一個匹配成功的庫為預設選中
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomePage(
          availableDatabases: matchedDbs,
          initialSelection: matchedDbs.first,
        ),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _authenticating = false;
      });
    }
  }
}

@override
Widget build(BuildContext context) {
  if (_loading) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }

  return Scaffold(
    appBar: AppBar(
      title: const Text('Login'),
    ),
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE3F2FD), Color(0xFFE8EAF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: 6,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Fix Asset Check',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onSubmitted: (_) => _onLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      tooltip: _obscurePassword ? '顯示密碼' : '隱藏密碼',
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Remember account'),
                        value: _rememberAccount,
                        onChanged: (v) {
                          setState(() {
                            _rememberAccount = v ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Remember password'),
                        value: _rememberPassword,
                        onChanged: (v) {
                          setState(() {
                            _rememberPassword = v ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: _authenticating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.login),
                    label: Text(_authenticating ? 'Signing in...' : 'Login'),
                    onPressed: _authenticating ? null : _onLogin,
                  ),
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

class HomePage extends StatefulWidget {
  final List<String> availableDatabases;
  final String initialSelection;
  const HomePage({super.key, required this.availableDatabases, required this.initialSelection});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late String _selectedDb;

  static const _kSuccessfulDbsKey = 'successfulDbs';
  static const _kPreferredDbKey = 'preferredDb';
  static const _kScanHistoryKey = 'scanHistory';
  // 新增：每筆掃描對應的資料庫名稱，與 _scanHistory 等長
  static const _kScanHistoryDbKey = 'scanHistoryDb';
  List<String> _scanHistory = [];
  List<String> _scanHistoryDb = [];

  // 內嵌掃描器（首頁直接掃描）
  final MobileScannerController _homeScanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: [BarcodeFormat.all],
  );
  String? _lastCodeHome;
  bool _handlingScan = false;
  // 針對首頁掃描：記錄各代碼最後處理時間，允許短冷卻後再次掃描
  final Map<String, DateTime> _homeLastHandledAt = {};
  // 查詢結果快取（依資料庫分區），避免跨資料庫顯示到其他庫的查詢結果
  final Map<String /* db */, Map<String /* code */, Map<String, dynamic>?>> _assetByDb = {};
  // 新增：會話到期檢查
  static const String _kSessionLoginAt = 'sessionLoginAt';
  static const int _kSessionMaxAgeHours = 24;
  Timer? _sessionExpireTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 以登入流程傳入的初始資料庫作為預設值，避免 LateInitializationError
    _selectedDb = widget.initialSelection;
    // 載入掃描記錄
    _loadScanHistory();
    // 第一幀後嘗試載入偏好資料庫（若存在且有效則覆蓋）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreferredDbIfAny();
    });
    // 啟動會話到期計時
    _setupSessionExpiry();
  }

  // 新增：設置或重設會話到期計時器
  Future<void> _setupSessionExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_kSessionLoginAt);
    if (ts == null) return;
    final loginAt = DateTime.tryParse(ts);
    if (loginAt == null) return;
    final now = DateTime.now().toUtc();
    final elapsed = now.difference(loginAt.toUtc());
    final maxAge = Duration(hours: _kSessionMaxAgeHours);
    final remain = maxAge - elapsed;
    if (remain <= Duration.zero) {
      if (mounted) _logout();
      return;
    }
    _sessionExpireTimer?.cancel();
    _sessionExpireTimer = Timer(remain, () {
      if (mounted) {
        _logout();
      }
    });
  }

  // 新增：前台時再次校驗是否已過期
  Future<void> _enforceSessionValidOnResume() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_kSessionLoginAt);
    if (ts == null) return;
    final loginAt = DateTime.tryParse(ts);
    if (loginAt == null) return;
    if (DateTime.now().toUtc().difference(loginAt.toUtc()) > Duration(hours: _kSessionMaxAgeHours)) {
      if (mounted) _logout();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enforceSessionValidOnResume();
    }
  }

  @override
  void dispose() {
    _sessionExpireTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 使用已存在的固定集群連線字串（與登入頁相同，用於查詢）
  static const String _kFixedBaseUriForQuery = _LoginPageState.kFixedMongoBaseUri;

  // 新增：格式化資料庫名稱供 UI 顯示（去除開頭的 "pw" 與結尾的 "asset"，其餘轉成大寫）
  String _formatDbDisplay(String db) {
    var start = 0;
    var end = db.length;
    final lower = db.toLowerCase();
    if (lower.startsWith('pw')) {
      start = 2;
    }
    if (lower.endsWith('asset')) {
      end -= 5;
    }
    if (start >= end) return db.toUpperCase();
    final core = db.substring(start, end);
    return core.toUpperCase();
  }

  // 將資料庫名稱附加到完整連線字串
  String _appendDbToMongoUriForQuery(String fullBaseUri, String dbName) {
    final qIndex = fullBaseUri.indexOf('?');
    final base = qIndex == -1 ? fullBaseUri : fullBaseUri.substring(0, qIndex);
    final query = qIndex == -1 ? '' : fullBaseUri.substring(qIndex);
    final baseNoSlash = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$baseNoSlash/$dbName$query';
  }

  // 嘗試以掃描字串從選定的資料庫查 fix_asset_list 對應文件
  Future<Map<String, dynamic>?> _fetchAssetByScannedCode(String raw) async {
    // 先做基本清理：去頭尾空白，並嘗試自字串中抽出第一段 24 位十六進位（若存在）
    String code = raw.trim();
    final match24 = RegExp(r'[a-fA-F0-9]{24}').firstMatch(code);
    if (match24 != null && code.length != 24) {
      code = match24.group(0)!; // 條碼若為 "ID: <hex>" 之類，取出 <hex>
    }

    final String uri = _appendDbToMongoUriForQuery(_kFixedBaseUriForQuery, _selectedDb);
    mongo.Db? db;
    try {
      db = await mongo.Db.create(uri);
      await db.open();
      final coll = db.collection('fix_asset_list');

      // 僅使用 ObjectId 依 _id 查詢（與實際資料類型一致）
      if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(code)) {
        debugPrint('Skip query: scanned "$raw" 不像 24 位 ObjectId（目前僅支援以 ObjectId 查詢）。');
        return null;
      }

      try {
        final objectId = mongo.ObjectId.fromHexString(code);
        final doc = await coll.findOne({'_id': objectId});
        if (doc != null) {
          debugPrint('Found document on $_selectedDb for ObjectId($code)');
          return doc.cast<String, dynamic>();
        }
        debugPrint('No document found on $_selectedDb for ObjectId($code)');
        return null;
      } catch (e) {
        debugPrint('Create ObjectId or query by ObjectId failed on $_selectedDb for "$code": $e');
        return null;
      }
    } catch (e) {
      debugPrint('Query error on $_selectedDb: $e');
      return null;
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  String _formatId(dynamic v) {
    if (v == null) return '';
    try {
      // 常見於 mongo_dart：toHexString()
      final hex = (v as dynamic).toHexString?.call();
      if (hex is String && hex.isNotEmpty) return hex;
    } catch (_) {}
    final s = v.toString();
    final m = RegExp(r'[a-fA-F0-9]{24}').firstMatch(s);
    return m?.group(0) ?? s;
  }

  String _formatWhen(dynamic v) {
    if (v == null) return '-';
    if (v is DateTime) return v.toLocal().toString().split(' ').first;
    if (v is String) {
      try {
        final dt = DateTime.parse(v);
        return dt.toLocal().toString().split(' ').first;
      } catch (_) {
        return v;
      }
    }
    return v.toString();
  }

  Future<void> _onHomeDetected(BarcodeCapture capture) async {
    if (_handlingScan) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    // 避免永久性去重，改為短冷卻：同一代碼 2 秒內不重複觸發
    final now = DateTime.now();
    final last = _homeLastHandledAt[code];
    if (last != null && now.difference(last) < const Duration(seconds: 2)) return;
    _homeLastHandledAt[code] = now;

    _handlingScan = true;
    await _addScanResult(code);
    await Future.delayed(const Duration(milliseconds: 600));
    _handlingScan = false;
  }

  Future<void> _loadScanHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final list = prefs.getStringList(_kScanHistoryKey) ?? [];
      _scanHistory = list;
      final dblist = prefs.getStringList(_kScanHistoryDbKey);
      if (dblist != null && dblist.length == list.length) {
        _scanHistoryDb = dblist;
      } else {
        // 若無舊資料或長度不一致，預設填目前選擇的 DB
        _scanHistoryDb = List<String>.filled(list.length, _selectedDb);
      }
    });
  }

  Future<void> _addScanResult(String code) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _scanHistory = [..._scanHistory, code];
      _scanHistoryDb = [..._scanHistoryDb, _selectedDb];
    });
    await prefs.setStringList(_kScanHistoryKey, _scanHistory);
    await prefs.setStringList(_kScanHistoryDbKey, _scanHistoryDb);
 
    // 立即針對該掃描值查詢目前所選資料庫
    final data = await _fetchAssetByScannedCode(code);
    if (!mounted) return;
    setState(() {
      final currentDbMap = Map<String, Map<String, dynamic>?>.from(_assetByDb[_selectedDb] ?? {});
      currentDbMap[code] = data;
      _assetByDb[_selectedDb] = currentDbMap;
    });
    final found = data != null;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(found ? '已找到對應項：$code' : '未在 ${_formatDbDisplay(_selectedDb)} 找到對應項：$code')),
    );
  }

  Future<void> _clearScanHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kScanHistoryKey);
    await prefs.remove(_kScanHistoryDbKey);
    if (!mounted) return;
    setState(() {
      _scanHistory = [];
      _scanHistoryDb = [];
    });
  }

  Future<void> _loadPreferredDbIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final preferred = prefs.getString(_kPreferredDbKey);
    if (preferred != null && widget.availableDatabases.contains(preferred) && preferred != _selectedDb) {
      if (!mounted) return;
      setState(() {
        _selectedDb = preferred;
      });
    }
  }

  Future<void> _applyDbSelection(String db) async {
    if (_selectedDb == db) return;
    setState(() {
      _selectedDb = db;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPreferredDbKey, db);
    // Reorder successfulDbs so that the newly selected db is prioritized next time
    final current = prefs.getStringList(_kSuccessfulDbsKey) ?? List<String>.from(widget.availableDatabases);
    final reordered = <String>[db, ...current.where((e) => e != db)];
    await prefs.setStringList(_kSuccessfulDbsKey, reordered);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    // 清理成功資料庫快取即可，帳密是否保留交由使用者的 Remember 選項控制
    await prefs.remove('successfulDbs');
    await prefs.remove('preferredDb');
    await prefs.remove('sessionLoginAt');
    _sessionExpireTimer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 12),
            Text(
              'PW Asset Check',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.storage, size: 18),
                const SizedBox(width: 6),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedDb,
                    items: widget.availableDatabases
                        .map((db) => DropdownMenuItem<String>(
                              value: db,
                              child: Text(_formatDbDisplay(db)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        _applyDbSelection(v);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    isDense: true,
                  ),
                ),
              ],
            ),
            const Spacer(),
            IconButton(
              tooltip: '清除掃描記錄',
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearScanHistory,
            ),
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double overlayPadding = 24;
          final double scanBoxWidth = constraints.maxWidth - overlayPadding * 2;
          final double scanBoxHeight = scanBoxWidth * 0.6; // 長方形預覽框
          final double topOffset = 24; // AppBar 下方一點距離

          final Rect box = Rect.fromLTWH(
            overlayPadding,
            topOffset,
            scanBoxWidth,
            scanBoxHeight,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: topOffset + scanBoxHeight + 24, // 掃描區塊高度
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: MobileScanner(
                        controller: _homeScanner,
                        fit: BoxFit.cover,
                        onDetect: _onHomeDetected,
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ScannerOverlayPainter(
                          boxRect: box,
                          borderRadius: 16,
                          borderColor: Colors.greenAccent,
                          borderWidth: 4,
                          cornerLength: 28,
                          overlayColor: Colors.white, // 區塊外為白色背景
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 下面顯示 Tag，並且可自動換行（多行顯示）
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: overlayPadding, vertical: 12),
                    child: ListView.separated(
                      itemCount: _scanHistory.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        // 最新在最前面（反向索引）
                        final codeIndex = _scanHistory.length - 1 - index;
                        final code = _scanHistory[codeIndex];
                        final dbForEntry = (_scanHistoryDb.length == _scanHistory.length)
                            ? _scanHistoryDb[codeIndex]
                            : _selectedDb; // 後備：若資料不一致，就以當前 DB 顯示
                        final data = _assetByDb[dbForEntry]?[code];
                        final idText = data != null ? _formatId(data['_id']) : code;
                        final from = data == null ? '-' : (data['From']?.toString() ?? '-');
                        final to = data == null ? '-' : (data['To']?.toString() ?? '-');
                        final whenStr = data == null ? '-' : _formatWhen(data['When']);
                        final oldAsset = data == null ? '-' : (data['Old Asset Code']?.toString() ?? '-');
                        final newAsset = data == null ? '-' : (data['New Asset Code']?.toString() ?? '-');
                        final sn = data == null ? '-' : (data['SN']?.toString() ?? '-');
                        final operatorStr = data == null ? '-' : (data['operator']?.toString() ?? '-');
                        final receiverStr = data == null ? '-' : (data['receiver']?.toString() ?? '-');
                        final details = data == null ? '-' : (data['Details']?.toString() ?? '-');
                        final tag = data == null ? '-' : (data['Tag']?.toString() ?? '-');
                        // disposal 標紅（不分大小寫）
                        final isDisposal = tag.toLowerCase().contains('disposal');
                        final tagColor = isDisposal ? Colors.red : Colors.white;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: scanBoxWidth,
                            decoration: BoxDecoration(
                              color: Colors.teal.shade700,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'ID: $idText',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white30, width: 1),
                                      ),
                                      child: Text(
                                        _formatDbDisplay(dbForEntry),
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('From: $from', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('To: $to', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('When: $whenStr', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('Old Asset Code: $oldAsset', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('New Asset Code: $newAsset', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('SN: $sn', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('operator: $operatorStr', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('receiver: $receiverStr', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('Details: $details', style: const TextStyle(color: Colors.white, fontSize: 14)),
                                Text('Tag: $tag', style: TextStyle(color: tagColor, fontSize: 14)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (_handlingScan)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(child: CircularProgressIndicator(color: Colors.teal)),
                ),
            ],
          );
        },
      ),
      // 移除原本需要點擊的掃描按鈕
      // floatingActionButton: null,
    );
  }
}

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: [BarcodeFormat.all],
  );

  bool _handling = false;
  DateTime? _lastDetectAt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetected(BarcodeCapture capture) async {
    if (_handling) return;
    // 簡單時間窗抑制，避免快速抖動導致多次觸發
    final now = DateTime.now();
    if (_lastDetectAt != null && now.difference(_lastDetectAt!) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastDetectAt = now;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    _handling = true;
    if (!mounted) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('掃描條碼'),
        actions: [
          IconButton(
            tooltip: '手電筒',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: '切換前/後相機',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double overlayPadding = 24;
          final double scanBoxWidth = constraints.maxWidth - overlayPadding * 2;
          final double scanBoxHeight = scanBoxWidth * 0.6; // 長方形預覽框（可掃條碼）
          final double topOffset = (constraints.maxHeight - scanBoxHeight) / 3; // 偏上位置

          return Stack(
            children: [
              // 相機預覽
              Positioned.fill(
                child: MobileScanner(
                  controller: _controller,
                  fit: BoxFit.cover,
                  onDetect: _onDetected,
                ),
              ),

              // 半透明遮罩 + 中央透明掃描框
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScannerOverlayPainter(
                    boxRect: Rect.fromLTWH(
                      overlayPadding,
                      topOffset,
                      scanBoxWidth,
                      scanBoxHeight,
                    ),
                    borderRadius: 16,
                    borderColor: Colors.greenAccent,
                    borderWidth: 4,
                    cornerLength: 28,
                    overlayColor: Colors.black.withOpacity(0.5),
                  ),
                ),
              ),

              // 提示文案
              Positioned(
                left: 0,
                right: 0,
                top: topOffset + scanBoxHeight + 16,
                child: const Center(
                  child: Text(
                    '請將條形碼置於框內自動對焦掃描',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),

              if (_handling)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 32,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  _ScannerOverlayPainter({
    required this.boxRect,
    this.borderRadius = 12,
    this.borderColor = Colors.white,
    this.borderWidth = 3,
    this.cornerLength = 24,
    this.overlayColor = const Color(0x99000000),
  });

  final Rect boxRect;
  final double borderRadius;
  final Color borderColor;
  final double borderWidth;
  final double cornerLength;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = overlayColor;
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;

    // 整個覆蓋
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, overlayPaint);

    // 中央透明窗
    final rrect = RRect.fromRectAndRadius(boxRect, Radius.circular(borderRadius));
    canvas.drawRRect(rrect, clearPaint);

    // 四角描邊
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // 上邊四角
    _drawCorner(canvas, Offset(boxRect.left, boxRect.top), true, true);
    _drawCorner(canvas, Offset(boxRect.right, boxRect.top), false, true);
    // 下邊四角
    _drawCorner(canvas, Offset(boxRect.left, boxRect.bottom), true, false);
    _drawCorner(canvas, Offset(boxRect.right, boxRect.bottom), false, false);

    canvas.restore();

    // 描繪圓角邊框線（可選）
    canvas.drawRRect(rrect, borderPaint);
  }

  void _drawCorner(Canvas canvas, Offset corner, bool isLeft, bool isTop) {
    final path = Path();
    final double dirX = isLeft ? 1 : -1;
    final double dirY = isTop ? 1 : -1;

    // 水平線
    path.moveTo(corner.dx, corner.dy);
    path.relativeLineTo(cornerLength * dirX, 0);
    // 垂直線
    path.moveTo(corner.dx, corner.dy);
    path.relativeLineTo(0, cornerLength * dirY);

    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return boxRect != oldDelegate.boxRect ||
        borderRadius != oldDelegate.borderRadius ||
        borderColor != oldDelegate.borderColor ||
        borderWidth != oldDelegate.borderWidth ||
        cornerLength != oldDelegate.cornerLength ||
        overlayColor != oldDelegate.overlayColor;
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _kMongoBaseUriKey = 'mongoBaseUri';
  static const _kCandidateDbsKey = 'candidateDbs';

  final TextEditingController _baseUriCtrl = TextEditingController();
  final TextEditingController _dbsCtrl = TextEditingController();

  bool _loading = true;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUriCtrl.text = prefs.getString(_kMongoBaseUriKey) ?? '';
    final list = prefs.getStringList(_kCandidateDbsKey) ?? [];
    _dbsCtrl.text = list.join(',');
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final uri = _baseUriCtrl.text.trim();
    final dbs = _dbsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMongoBaseUriKey, uri);
    await prefs.setStringList(_kCandidateDbsKey, dbs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUriCtrl.dispose();
    _dbsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MongoDB connection string (without credentials preferred):',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseUriCtrl,
                    decoration: const InputDecoration(
                      hintText: 'mongodb+srv://cluster-hostname/?retryWrites=true&w=majority',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  const Text('Candidate database names (comma-separated):',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _dbsCtrl,
                    decoration: const InputDecoration(
                      hintText: 'db1,db2,db3',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                      onPressed: _save,
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
