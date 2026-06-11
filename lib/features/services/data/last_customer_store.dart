/// Oxirgi yuborilgan buyurtmachi rekvizitlari (F.I.SH, STIR/INN, telefon,
/// e-mail) — keyingi arizada foydalanuvchi qaytadan yozmasligi uchun lokal
/// saqlanadi. Profil ma'lumotlarida STIR/INN va e-mail yo'q, shuning uchun
/// ularni aynan shu yerda eslab qolamiz.
library;

import 'package:shared_preferences/shared_preferences.dart';

class LastCustomer {
  const LastCustomer({
    this.name = '',
    this.tin = '',
    this.phone = '',
    this.email = '',
  });

  final String name;
  final String tin;
  final String phone;
  final String email;

  bool get isEmpty =>
      name.isEmpty && tin.isEmpty && phone.isEmpty && email.isEmpty;
}

class LastCustomerStore {
  const LastCustomerStore();

  static const _nameKey = 'last_customer_name_v1';
  static const _tinKey = 'last_customer_tin_v1';
  static const _phoneKey = 'last_customer_phone_v1';
  static const _emailKey = 'last_customer_email_v1';

  Future<LastCustomer?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final c = LastCustomer(
      name: prefs.getString(_nameKey) ?? '',
      tin: prefs.getString(_tinKey) ?? '',
      phone: prefs.getString(_phoneKey) ?? '',
      email: prefs.getString(_emailKey) ?? '',
    );
    return c.isEmpty ? null : c;
  }

  Future<void> save(LastCustomer c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, c.name.trim());
    await prefs.setString(_tinKey, c.tin.trim());
    await prefs.setString(_phoneKey, c.phone.trim());
    await prefs.setString(_emailKey, c.email.trim());
  }
}
