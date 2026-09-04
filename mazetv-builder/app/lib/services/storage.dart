import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';

class Storage {
  static const _kAccount = 'account';
  static const _kLastChannel = 'last_channel';

  static Future<Account?> loadAccount() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kAccount);
    return s == null ? null : Account.fromJson(s);
  }

  static Future<void> saveAccount(Account a) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAccount, a.toJson());
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAccount);
  }

  static Future<void> saveLastChannel(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastChannel, id);
  }

  static Future<String?> lastChannel() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastChannel);
  }
}
