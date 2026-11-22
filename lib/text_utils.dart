/// یکسان‌سازی متن فارسی برای جستجو/مرتب‌سازی:
/// «ي/ك» عربی ← «ی/ک»، ارقام فارسی و عربی ← انگلیسی، حذف نیم‌فاصله و کشیده.
String normalizeFa(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().runes) {
    switch (c) {
      case 0x064A: // ي
      case 0x0649: // ى
        b.write('ی');
      case 0x0643: // ك
        b.write('ک');
      case 0x200C: // نیم‌فاصله
      case 0x0640: // کشیده
        break;
      default:
        if (c >= 0x06F0 && c <= 0x06F9) {
          b.writeCharCode(0x30 + c - 0x06F0); // ۰-۹
        } else if (c >= 0x0660 && c <= 0x0669) {
          b.writeCharCode(0x30 + c - 0x0660); // ٠-٩
        } else {
          b.writeCharCode(c);
        }
    }
  }
  return b.toString();
}

/// مرتب‌سازی طبیعی: «جلد ۲» قبل از «جلد ۱۰»
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(normalizeFa(a)).map((m) => m[0]!).toList();
  final y = re.allMatches(normalizeFa(b)).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final nx = BigInt.tryParse(x[i]), ny = BigInt.tryParse(y[i]);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}
