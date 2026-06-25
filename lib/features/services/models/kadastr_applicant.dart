/// Shared "applicant" contact for the combined Kadastr calculator flow.
///
/// When several services are selected, the contact (ism / telefon / manzil) is
/// collected ONCE on the lead form, then pre-filled into each selected
/// service's own form so it's never re-entered. Each service still submits its
/// own order.
library;

class SharedApplicant {
  const SharedApplicant({
    required this.name,
    required this.phone, // national 9 digits, e.g. "90 123-45-67"
    this.tin = '',
    this.email = '',
    this.address = '',
    this.cadastreNumber = '',
  });

  final String name;
  final String phone;
  final String tin;
  final String email;
  final String address;
  final String cadastreNumber;

  /// Full +998 phone for order payloads / display. Tolerates a phone that
  /// already carries the 998 country code (e.g. taken from a wizard draft).
  String get fullPhone {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('998')) digits = digits.substring(3);
    return '+998 $digits';
  }
}
