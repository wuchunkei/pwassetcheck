import 'package:mongo_dart/mongo_dart.dart' as mongo;

// Quick diagnostic script to check whether a given username exists in
// specific databases and whether the stored password matches the expected one.
// Usage: dart run scripts/check_mongo_user.dart
Future<void> main() async {
  const baseUri = '//'; // redacted for public repo
  const username = 'wuchunkei';
  const expectedPassword = '********'; // redacted
  final candidates = <String>['pwhkasset', 'pwcnasset', 'pwtestasset'];

  for (final dbName in candidates) {
    final uri = _appendDbToMongoUri(baseUri, dbName);
    mongo.Db? db;
    try {
      db = await mongo.Db.create(uri);
      await db.open();
      final users = db.collection('users');
      final doc = await users.findOne({'username': username});
      final stored = doc != null ? (doc['password']?.toString() ?? '') : null;
      final match = stored == expectedPassword;
      print('[
${dbName}] userExists=${doc != null} passwordMatch=$match storedPassword=${stored ?? '(null)'} last_login=${doc != null ? doc['last_login'] : '(n/a)'}');
    } catch (e) {
      print('[${dbName}] ERROR: $e');
    } finally {
      try { await db?.close(); } catch (_) {}
    }
  }
}

String _appendDbToMongoUri(String fullBaseUri, String dbName) {
  final qIndex = fullBaseUri.indexOf('?');
  final base = qIndex == -1 ? fullBaseUri : fullBaseUri.substring(0, qIndex);
  final query = qIndex == -1 ? '' : fullBaseUri.substring(qIndex);
  final baseNoSlash = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$baseNoSlash/$dbName$query';
}