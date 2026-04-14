class NotificationSettings {
  final bool smsMoneyIn;
  final bool smsMoneyOut;

  NotificationSettings({
    required this.smsMoneyIn,
    required this.smsMoneyOut,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      smsMoneyIn: json['sms_money_in'] ?? true,
      smsMoneyOut: json['sms_money_out'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sms_money_in': smsMoneyIn,
      'sms_money_out': smsMoneyOut,
    };
  }

  NotificationSettings copyWith({
    bool? smsMoneyIn,
    bool? smsMoneyOut,
  }) {
    return NotificationSettings(
      smsMoneyIn: smsMoneyIn ?? this.smsMoneyIn,
      smsMoneyOut: smsMoneyOut ?? this.smsMoneyOut,
    );
  }
}
