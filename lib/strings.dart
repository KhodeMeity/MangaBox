/// همه‌ی متن‌های رابط (فارسی)
class S {
  static const appName = 'MangaBox';
  static const add = 'افزودن';
  static const addFiles = 'افزودن فایل';
  static const scanFolder = 'اسکن پوشه';
  static const emptyTitle = 'کتابخانه خالی است';
  static const emptyHint =
      'با دکمه‌ی «افزودن» فایل‌های CBZ یا PDF را وارد کنید.\nفایل‌ها را از تلگرام یا فایل‌منیجر هم می‌توانید مستقیم با MangaBox باز کنید.';
  static const opening = 'در حال باز کردن…';
  static const openFailed = 'باز کردن فایل ممکن نشد';
  static const rarUnsupported = 'این فایل RAR واقعی است (CBR) و هنوز پشتیبانی نمی‌شود. آن را به CBZ تبدیل کنید.';
  static const noImages = 'هیچ تصویری داخل فایل پیدا نشد';
  static const badFormat = 'فرمت فایل پشتیبانی نمی‌شود';
  static const pdfLocked = 'این PDF رمز دارد و باز نمی‌شود';
  static const pageFailed = 'بارگذاری صفحه ناموفق بود';
  static const noFilePicked = 'فایلی انتخاب نشد';
  static const noComicInFolder = 'در این پوشه کمیکی پیدا نشد';
  static const removeTitle = 'حذف از کتابخانه؟';
  static const removeBody = 'فقط از فهرست حذف می‌شود؛ فایل اصلی پاک نمی‌شود.';
  static const cancel = 'انصراف';
  static const remove = 'حذف';
  static const lockRotation = 'قفل چرخش صفحه';
  static const modeLtr = 'ورق‌زدن افقی (چپ‌به‌راست)';
  static const modeRtl = 'مانگا (راست‌به‌چپ)';
  static const modeWebtoon = 'وبتون (اسکرول عمودی)';

  static String added(int n) => '${fa(n)} کمیک اضافه شد';

  static String fa(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'\d'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);
}
