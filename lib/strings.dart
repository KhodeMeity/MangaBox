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
  static const rar5Unsupported = 'این فایل RAR نسخه‌ی ۵ است و هنوز پشتیبانی نمی‌شود. آن را به‌صورت CBZ (یا RAR4) ذخیره کنید.';
  static const rarBroken = 'استخراج فایل RAR ناموفق بود (فایل خراب یا رمزدار است)';
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

  static const searchHint = 'جستجو در کتابخانه…';
  static const searchTooltip = 'جستجو';
  static const closeSearch = 'بستن جستجو';
  static const sortTooltip = 'مرتب‌سازی';
  static const sortLastRead = 'آخرین مطالعه';
  static const sortAdded = 'تازه‌ترین افزوده‌شده';
  static const sortName = 'نام (الف تا ی)';
  static const sortProgress = 'بیشترین پیشرفت';
  static const filterAll = 'همه';
  static const filterReading = 'در حال خواندن';
  static const filterFinished = 'تمام‌شده';
  static const filterUnread = 'خوانده‌نشده';
  static const noResults = 'نتیجه‌ای پیدا نشد';

  static const smartZoom = 'زوم هوشمند روی پنل';
  static const smartZoomOn = 'زوم هوشمند روشن شد: دابل‌تپ روی هر پنل';
  static const smartZoomOff = 'زوم هوشمند خاموش شد';

  static const dualPage = 'نمایش دو صفحه‌ای (حالت افقی)';
  static const coverAlone = 'صفحه‌ی اول تنها (جلد)';

  static String added(int n) => '${fa(n)} کمیک اضافه شد';

  static String fa(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'\d'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);
}
