enum PaymentMethod {
  payme,
  uzum,
  click,
  paynet;

  String get label => switch (this) {
    PaymentMethod.payme => 'payme',
    PaymentMethod.uzum => 'uzum',
    PaymentMethod.click => 'click',
    PaymentMethod.paynet => 'paynet',
  };

  String get assetPath => switch (this) {
    PaymentMethod.payme => 'assets/images/payment/payme.svg',
    PaymentMethod.uzum => 'assets/images/payment/uzum.svg',
    PaymentMethod.click => 'assets/images/payment/click.svg',
    PaymentMethod.paynet => 'assets/images/payment/paynet.svg',
  };

  /// Per-logo render height that normalizes visual weight across brands
  /// whose SVG viewBoxes have different aspect ratios (click is compact,
  /// paynet is very wide).
  double get renderHeight => switch (this) {
    PaymentMethod.payme => 22,
    PaymentMethod.uzum => 22,
    PaymentMethod.click => 26,
    PaymentMethod.paynet => 18,
  };
}
