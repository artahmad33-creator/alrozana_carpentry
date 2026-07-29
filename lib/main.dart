import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// المكتبات السحابية
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

List<ProjectModel> globalProjects = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // الربط السحابي بـ Supabase
  await Supabase.initialize(
    url: 'https://zsqrgmahenngftgzpvdq.supabase.co',
    anonKey: 'sb_publishable_536GEoJCSbPmcv_oALK6cg_wjywpHYa',
  );

  await AppSettings.loadSettings();
  globalProjects = await ProjectManager.loadProjectsFromCloud();

  runApp(const AlrozanaApp());
}

// ---------------------------------------------------------
// دالة تنسيق الأرقام
// ---------------------------------------------------------
String formatMoney(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  final re = RegExp(r'\B(?=(\d{3})+(?!\d))');
  parts[0] = parts[0].replaceAllMapped(re, (match) => ',');
  return parts.join('.');
}

// ---------------------------------------------------------
// الألوان
// ---------------------------------------------------------
class AppPalette {
  static const Color cream = Color(0xFFEBE6DF);
  static const Color mauve = Color(0xFFAC95A5);
  static const Color teal = Color(0xFF9ECCC9);
  static const Color iceWhite = Color(0xFFDFE4E5);
  static const Color stoneGrey = Color(0xFFA5A9A9);
  static const Color plum = Color(0xFF5F2D4E);
  static const List<Color> allColors = [
    cream,
    mauve,
    teal,
    iceWhite,
    stoneGrey,
    plum
  ];
}

// ---------------------------------------------------------
// الإعدادات
// ---------------------------------------------------------
class AppSettings {
  static String ownerPin = "123456";
  static List<String> employeePins = ["111111"];
  static String appTitle = "منجرة الروزنة للأعمال الخشبية";
  static String headerSubtitle = "نظام إدارة الطلبات والمشاريع (سحابي)";
  static String footerMessage = "نعمل بشغف لإرضائكم - إدارة منجرة الروزنة";
  static String fontFamily = 'Tahoma';
  static double baseFontSize = 14.0;
  static Color primaryColor = AppPalette.plum;

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    ownerPin = prefs.getString('ownerPin') ?? "123456";
    employeePins = prefs.getStringList('employeePins') ?? ["111111"];
    appTitle = prefs.getString('appTitle') ?? "منجرة الروزنة للأعمال الخشبية";
    headerSubtitle =
        prefs.getString('headerSubtitle') ?? "نظام إدارة الطلبات والمشاريع";
    footerMessage = prefs.getString('footerMessage') ??
        "نعمل بشغف لإرضائكم - إدارة منجرة الروزنة";
    fontFamily = prefs.getString('fontFamily') ?? 'Tahoma';
    baseFontSize = prefs.getDouble('baseFontSize') ?? 14.0;
    int colorValue = prefs.getInt('primaryColor') ?? AppPalette.plum.value;
    primaryColor = Color(colorValue);
  }

  static Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ownerPin', ownerPin);
    await prefs.setStringList('employeePins', employeePins);
    await prefs.setString('appTitle', appTitle);
    await prefs.setString('headerSubtitle', headerSubtitle);
    await prefs.setString('footerMessage', footerMessage);
    await prefs.setString('fontFamily', fontFamily);
    await prefs.setDouble('baseFontSize', baseFontSize);
    await prefs.setInt('primaryColor', primaryColor.value);
  }
}

// ---------------------------------------------------------
// نماذج البيانات
// ---------------------------------------------------------
class PaymentRecord {
  double amount;
  String date;
  PaymentRecord({required this.amount, required this.date});

  Map<String, dynamic> toJson() => {'amount': amount, 'date': date};
  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
        amount: (json['amount'] ?? 0).toDouble(),
        date: json['date'] ?? '',
      );
}

class ProjectModel {
  int projectId;
  String clientName;
  String workType;
  double contractValue;
  List<PaymentRecord> payments;
  String notes;
  double progress;
  String? imageUrl;

  ProjectModel({
    required this.projectId,
    required this.clientName,
    required this.workType,
    required this.contractValue,
    required this.payments,
    required this.notes,
    required this.progress,
    this.imageUrl,
  });

  String get projectNumber => 'R-C-${projectId.toString().padLeft(2, '0')}';
  double get totalPaid => payments.fold(0.0, (sum, item) => sum + item.amount);
  double get remainingAmount => contractValue - totalPaid;

  String get status {
    if (progress >= 1.0) return 'منجز بالكامل';
    if (progress > 0.7) return 'قيد الدهان والتركيب';
    if (progress > 0.3) return 'التجميع والقص';
    return 'تحضير المواد الخشبية';
  }

  Color get progressColor {
    if (progress <= 0.50) return const Color(0xFFD9534F);
    if (progress <= 0.80) return const Color(0xFFF0AD4E);
    return const Color(0xFF5CB85C);
  }

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'clientName': clientName,
        'workType': workType,
        'contractValue': contractValue,
        'payments': payments.map((p) => p.toJson()).toList(),
        'notes': notes,
        'progress': progress,
        'imageUrl': imageUrl,
      };

  factory ProjectModel.fromJson(Map<String, dynamic> json) => ProjectModel(
        projectId: json['projectId'] ?? 0,
        clientName: json['clientName'] ?? '',
        workType: json['workType'] ?? '',
        contractValue: (json['contractValue'] ?? 0).toDouble(),
        payments: (json['payments'] as List?)
                ?.map((p) => PaymentRecord.fromJson(p))
                .toList() ??
            [],
        notes: json['notes'] ?? '',
        progress: (json['progress'] ?? 0).toDouble(),
        imageUrl: json['imageUrl'],
      );
}

// ---------------------------------------------------------
// مدير المشاريع السحابي (Supabase)
// ---------------------------------------------------------
class ProjectManager {
  static const String _bucketName = 'alrozana-images';

  static Future<void> saveProjectsToCloud(List<ProjectModel> projects) async {
    try {
      final supabase = Supabase.instance.client;
      List<Map<String, dynamic>> jsonList =
          projects.map((p) => p.toJson()).toList();
      String jsonData = jsonEncode(jsonList);

      final bytes = Uint8List.fromList(utf8.encode(jsonData));
      await supabase.storage.from(_bucketName).uploadBinary(
            'projects_data.json',
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
    } catch (e) {
      debugPrint('خطأ في حفظ المشاريع للسحابة: $e');
    }
  }

  static Future<List<ProjectModel>> loadProjectsFromCloud() async {
    try {
      final supabase = Supabase.instance.client;
      final Uint8List data = await supabase.storage
          .from(_bucketName)
          .download('projects_data.json');
      String jsonData = utf8.decode(data);
      List<dynamic> jsonList = jsonDecode(jsonData);
      return jsonList.map((j) => ProjectModel.fromJson(j)).toList();
    } catch (e) {
      debugPrint('لم يتم العثور على بيانات سحابية، سيتم استخدام الافتراضية.');
      return _getDefaultProjects();
    }
  }

  static List<ProjectModel> _getDefaultProjects() {
    return [
      ProjectModel(
          projectId: 1,
          clientName: 'فيلا أستاذ عبدالله',
          workType: 'أبواب خشبية وخزائن ملابس',
          contractValue: 50000,
          payments: [PaymentRecord(amount: 25000, date: '2026-06-01')],
          notes: 'تم أخذ القياسات بدقة وبدء العمل.',
          progress: 0.80),
      ProjectModel(
          projectId: 2,
          clientName: 'مشروع مطعم المجلس',
          workType: 'ديكورات وجدران خشبية',
          contractValue: 75000,
          payments: [PaymentRecord(amount: 30000, date: '2026-06-10')],
          notes: 'استخدام خشب بلوط طبيعي.',
          progress: 1.0),
    ];
  }
}

// ---------------------------------------------------------
// قلب التطبيق
// ---------------------------------------------------------
class AlrozanaApp extends StatefulWidget {
  const AlrozanaApp({Key? key}) : super(key: key);

  static void switchTheme(BuildContext context) {
    context.findAncestorStateOfType<_AlrozanaAppState>()?.toggleTheme();
  }

  static void refreshApp(BuildContext context) {
    context.findAncestorStateOfType<_AlrozanaAppState>()?.refresh();
  }

  @override
  State<AlrozanaApp> createState() => _AlrozanaAppState();
}

class _AlrozanaAppState extends State<AlrozanaApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.system) {
        _themeMode = Theme.of(context).brightness == Brightness.dark
            ? ThemeMode.light
            : ThemeMode.dark;
      } else {
        _themeMode =
            _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      }
    });
  }

  void refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ALROZANA CARPENTRY',
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: AppSettings.primaryColor, brightness: Brightness.light),
        scaffoldBackgroundColor: AppPalette.cream,
        fontFamily: AppSettings.fontFamily,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: AppSettings.primaryColor, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        fontFamily: AppSettings.fontFamily,
      ),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
      home: const PinLoginScreen(),
    );
  }
}

// ---------------------------------------------------------
// شاشة الدخول (الرقم السري)
// ---------------------------------------------------------
class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({Key? key}) : super(key: key);
  @override
  _PinLoginScreenState createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  String currentPin = "";

  void _addNumber(String number) {
    SystemSound.play(SystemSoundType.click);
    if (currentPin.length < 6) {
      setState(() => currentPin += number);
      if (currentPin.length == 6) _verifyPin();
    }
  }

  void _deleteNumber() {
    SystemSound.play(SystemSoundType.click);
    if (currentPin.isNotEmpty) {
      setState(
          () => currentPin = currentPin.substring(0, currentPin.length - 1));
    }
  }

  void _verifyPin() {
    if (currentPin == AppSettings.ownerPin) {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const DashboardScreen(isOwner: true)));
    } else if (AppSettings.employeePins.contains(currentPin)) {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const DashboardScreen(isOwner: false)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرقم السري خاطئ!'), backgroundColor: Colors.red));
      setState(() => currentPin = "");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
              child: Image.asset('assets/images/login_background.png',
                  fit: BoxFit.cover)),
          Positioned.fill(
              child:
                  Container(color: AppSettings.primaryColor.withOpacity(0.8))),
          SafeArea(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppPalette.cream.withOpacity(0.9)),
                      child: ClipOval(
                          child: Image.asset('assets/images/logo.png',
                              width: 160, height: 160, fit: BoxFit.cover)),
                    ),
                    const SizedBox(height: 25),
                    Text(AppSettings.appTitle,
                        style: TextStyle(
                            fontFamily: AppSettings.fontFamily,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    const SizedBox(height: 30),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                            6,
                            (index) => Container(
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: index < currentPin.length
                                          ? AppPalette.teal
                                          : Colors.white.withOpacity(0.3),
                                      border: Border.all(
                                          color: Colors.white, width: 1.5)),
                                )),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3, childAspectRatio: 1.5),
                          itemCount: 12,
                          itemBuilder: (context, index) {
                            if (index == 9) return const SizedBox.shrink();
                            if (index == 11) {
                              return IconButton(
                                  splashColor:
                                      AppPalette.mauve.withOpacity(0.4),
                                  icon: const Icon(Icons.backspace,
                                      color: Colors.white, size: 28),
                                  onPressed: _deleteNumber);
                            }
                            String num = index == 10 ? "0" : "${index + 1}";
                            return InkWell(
                                onTap: () => _addNumber(num),
                                splashColor: AppPalette.mauve.withOpacity(0.4),
                                customBorder: const CircleBorder(),
                                child: Center(
                                    child: Text(num,
                                        style: TextStyle(
                                            fontFamily: AppSettings.fontFamily,
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white))));
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// شاشة الإعدادات
// ---------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  final VoidCallback onSettingsSaved;
  final List<ProjectModel> allProjects;
  const SettingsScreen(
      {Key? key, required this.onSettingsSaved, required this.allProjects})
      : super(key: key);
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _titleController = TextEditingController(text: AppSettings.appTitle);
  final _subtitleController =
      TextEditingController(text: AppSettings.headerSubtitle);
  final _footerController =
      TextEditingController(text: AppSettings.footerMessage);
  final _ownerPinController = TextEditingController(text: AppSettings.ownerPin);
  late TextEditingController _employeePinController;
  double _tempFontSize = AppSettings.baseFontSize;
  String _tempFontFamily = AppSettings.fontFamily;
  Color _tempPrimaryColor = AppSettings.primaryColor;
  final List<String> _fonts = [
    'Tahoma',
    'Arial',
    'Courier New',
    'Times New Roman',
    'Verdana'
  ];

  @override
  void initState() {
    super.initState();
    _employeePinController =
        TextEditingController(text: AppSettings.employeePins.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('الإعدادات والتقارير',
              style: TextStyle(fontFamily: AppSettings.fontFamily))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('ألوان التطبيق (لوحة الفرش)',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: AppPalette.allColors.map((color) {
              return GestureDetector(
                onTap: () => setState(() => _tempPrimaryColor = color),
                child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _tempPrimaryColor == color
                                ? Colors.black
                                : Colors.transparent,
                            width: 3))),
              );
            }).toList(),
          ),
          const Divider(height: 40),
          Text('التقارير والطباعة العامة (PDF)',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('المشاريع المنتهية'),
                  onPressed: () => DashboardScreen.generatePdfReportStatic(
                      context,
                      'تقرير المشاريع المنتهية',
                      widget.allProjects
                          .where((p) => p.progress >= 1.0)
                          .toList())),
              ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('المشاريع الحالية'),
                  onPressed: () => DashboardScreen.generatePdfReportStatic(
                      context,
                      'تقرير المشاريع النشطة',
                      widget.allProjects
                          .where((p) => p.progress < 1.0)
                          .toList())),
              ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('تقرير مالي كامل'),
                  onPressed: () => DashboardScreen.generatePdfReportStatic(
                      context, 'التقرير المالي الشامل', widget.allProjects)),
            ],
          ),
          const Divider(height: 40),
          Text('إعدادات الخطوط',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
              value: _tempFontFamily,
              items: _fonts
                  .map((f) => DropdownMenuItem(
                      value: f,
                      child: Text(f, style: TextStyle(fontFamily: f))))
                  .toList(),
              onChanged: (v) => setState(() => _tempFontFamily = v!),
              decoration: const InputDecoration(
                  labelText: 'نوع الخط', border: OutlineInputBorder())),
          const SizedBox(height: 15),
          Text('حجم الخط الأساسي: ${_tempFontSize.toInt()}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Slider(
              value: _tempFontSize,
              min: 10,
              max: 24,
              divisions: 14,
              label: _tempFontSize.toString(),
              onChanged: (v) => setState(() => _tempFontSize = v)),
          const Divider(height: 40),
          Text('إعدادات النظام',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 10),
          TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                  labelText: 'اسم المنجرة الرئيسي',
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: _subtitleController,
              decoration: const InputDecoration(
                  labelText: 'العنوان الفرعي', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: _footerController,
              decoration: const InputDecoration(
                  labelText: 'رسالة التذييل', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(
              controller: _ownerPinController,
              decoration: const InputDecoration(
                  labelText: 'كلمة مرور الإدارة (6 أرقام)',
                  border: OutlineInputBorder()),
              maxLength: 6),
          const SizedBox(height: 10),
          TextField(
              controller: _employeePinController,
              decoration: const InputDecoration(
                  labelText: 'كلمة مرور الموظفين (6 أرقام)',
                  border: OutlineInputBorder()),
              maxLength: 6),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15)),
            onPressed: () async {
              setState(() {
                AppSettings.appTitle = _titleController.text;
                AppSettings.headerSubtitle = _subtitleController.text;
                AppSettings.footerMessage = _footerController.text;
                AppSettings.baseFontSize = _tempFontSize;
                AppSettings.fontFamily = _tempFontFamily;
                AppSettings.primaryColor = _tempPrimaryColor;
                if (_ownerPinController.text.length == 6)
                  AppSettings.ownerPin = _ownerPinController.text;
                if (_employeePinController.text.length == 6)
                  AppSettings.employeePins[0] = _employeePinController.text;
              });
              await AppSettings.saveSettings();
              AlrozanaApp.refreshApp(context);
              widget.onSettingsSaved();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حفظ التعديلات',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// لوحة التحكم الرئيسية
// ---------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  final bool isOwner;
  const DashboardScreen({Key? key, required this.isOwner}) : super(key: key);

  static Future<void> generatePdfReportStatic(BuildContext context,
      String reportTitle, List<ProjectModel> reportProjects) async {
    try {
      final pdf = pw.Document();
      pw.Font font;
      pw.Font boldFont;
      try {
        font = await PdfGoogleFonts.cairoRegular();
        boldFont = await PdfGoogleFonts.cairoBold();
      } catch (e) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      Uint8List? logoBytes;
      try {
        final ByteData data = await rootBundle.load('assets/images/logo.png');
        logoBytes = data.buffer.asUint8List();
      } catch (_) {}

      String printDateTime = DateTime.now().toString().substring(0, 19);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          footer: (pw.Context context) {
            String pageNumFormatted =
                context.pageNumber.toString().padLeft(2, '0');
            return pw.Container(
              alignment: pw.Alignment.centerLeft,
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(pageNumFormatted,
                      style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 9,
                          color: PdfColors.grey700)),
                  pw.Text(AppSettings.footerMessage,
                      style: pw.TextStyle(
                          font: font, fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            );
          },
          build: (pw.Context context) {
            return [
              if (logoBytes != null) ...[
                pw.Center(
                    child: pw.Image(pw.MemoryImage(logoBytes),
                        width: 110, height: 110)),
                pw.SizedBox(height: 10)
              ],
              pw.Center(
                  child: pw.Text(AppSettings.appTitle,
                      style: pw.TextStyle(font: boldFont, fontSize: 16))),
              pw.SizedBox(height: 4),
              pw.Center(
                  child: pw.Text(reportTitle,
                      style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 12,
                          color: PdfColors.brown))),
              pw.SizedBox(height: 6),
              pw.Center(
                  child: pw.Text('تاريخ ووقت الطباعة: $printDateTime',
                      style: pw.TextStyle(
                          font: font, fontSize: 9, color: PdfColors.grey700))),
              pw.SizedBox(height: 15),
              pw.Table(
                border:
                    pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.brown),
                    children: [
                      'المشروع',
                      'العميل',
                      'النوع',
                      'العقد',
                      'المدفوع',
                      'المتبقي',
                      'الإنجاز'
                    ]
                        .map((header) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Center(
                                child: pw.Text(header,
                                    style: pw.TextStyle(
                                        font: boldFont,
                                        color: PdfColors.white,
                                        fontSize: 9)))))
                        .toList(),
                  ),
                  ...reportProjects.map((p) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Center(
                                child: pw.Text(p.projectNumber,
                                    style: pw.TextStyle(
                                        font: boldFont,
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 9)))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Center(
                                child: pw.Text(p.clientName,
                                    style: pw.TextStyle(
                                        font: font, fontSize: 8)))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Center(
                                child: pw.Text(p.workType,
                                    style: pw.TextStyle(
                                        font: font, fontSize: 8)))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Center(
                                child: pw.Text(
                                    '${formatMoney(p.contractValue)} د.إ',
                                    style: pw.TextStyle(
                                        font: font, fontSize: 8)))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Center(
                                child: pw.Text(
                                    '${formatMoney(p.totalPaid)} د.إ',
                                    style: pw.TextStyle(
                                        font: font, fontSize: 8)))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Center(
                                child: pw.Text(
                                    '${formatMoney(p.remainingAmount)} د.إ',
                                    style: pw.TextStyle(
                                        font: font, fontSize: 8)))),
                        pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Center(
                                child: pw.Text('${(p.progress * 100).toInt()}%',
                                    style: pw.TextStyle(
                                        font: font, fontSize: 8)))),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Divider(),
              pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        'إجمالي العقود: ${formatMoney(reportProjects.fold(0.0, (sum, p) => sum + p.contractValue))} د.إ',
                        style: pw.TextStyle(font: boldFont, fontSize: 10)),
                    pw.Text(
                        'إجمالي المتبقي: ${formatMoney(reportProjects.fold(0.0, (sum, p) => sum + p.remainingAmount))} د.إ',
                        style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 10,
                            color: PdfColors.red800)),
                  ]),
              pw.Spacer(),
            ];
          },
        ),
      );
      await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: '$reportTitle.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ في الطباعة: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _isGridView = true;
  bool _isGroupedByClient = false;
  bool _isLoadingImage = false;
  String _searchQuery = "";

  late AnimationController _glowController;
  final List<ProjectModel> _projects = globalProjects;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  List<ProjectModel> get sortedProjects {
    List<ProjectModel> filtered = _projects.where((p) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return p.clientName.toLowerCase().contains(query) ||
          p.projectId.toString().padLeft(2, '0').contains(query) ||
          p.projectNumber.toLowerCase().contains(query);
    }).toList();
    List<ProjectModel> active =
        filtered.where((p) => p.progress < 1.0).toList();
    List<ProjectModel> completed =
        filtered.where((p) => p.progress >= 1.0).toList();
    active.sort((a, b) => b.projectId.compareTo(a.projectId));
    completed.sort((a, b) => b.projectId.compareTo(a.projectId));
    return [...active, ...completed];
  }

  int _getNextProjectId() => _projects.isEmpty
      ? 1
      : _projects.map((p) => p.projectId).reduce((a, b) => a > b ? a : b) + 1;

  void _showProjectDialog({ProjectModel? projectToEdit}) {
    final bool isEditing = projectToEdit != null;
    final clientController =
        TextEditingController(text: isEditing ? projectToEdit.clientName : '');
    final workTypeController =
        TextEditingController(text: isEditing ? projectToEdit.workType : '');
    final contractValueController = TextEditingController(
        text: isEditing ? projectToEdit.contractValue.toString() : '');
    final notesController =
        TextEditingController(text: isEditing ? projectToEdit.notes : '');
    double progressValue = isEditing ? projectToEdit.progress : 0.0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'تعديل' : 'إضافة',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: clientController,
                    decoration: const InputDecoration(labelText: 'الاسم')),
                TextField(
                    controller: workTypeController,
                    decoration: const InputDecoration(labelText: 'نوع العمل')),
                TextField(
                    controller: contractValueController,
                    decoration: const InputDecoration(labelText: 'القيمة')),
                Slider(
                    value: progressValue,
                    onChanged: (v) => setDialogState(() => progressValue = v)),
                TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'ملاحظات')),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                setState(() {
                  if (isEditing) {
                    projectToEdit.clientName = clientController.text;
                    projectToEdit.workType = workTypeController.text;
                    projectToEdit.contractValue =
                        double.tryParse(contractValueController.text) ?? 0;
                    projectToEdit.progress = progressValue;
                    projectToEdit.notes = notesController.text;
                  } else {
                    _projects.add(ProjectModel(
                        projectId: _getNextProjectId(),
                        clientName: clientController.text,
                        workType: workTypeController.text,
                        contractValue:
                            double.tryParse(contractValueController.text) ?? 0,
                        payments: [],
                        notes: notesController.text,
                        progress: progressValue));
                  }
                });
                await ProjectManager.saveProjectsToCloud(_projects);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('حفظ'),
            )
          ],
        ),
      ),
    );
  }

  void _confirmDeleteProject(ProjectModel project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.red)),
        content: Text('حذف "${project.clientName}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () async {
                setState(() => _projects.remove(project));
                await ProjectManager.saveProjectsToCloud(_projects);
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف')),
        ],
      ),
    );
  }

  // --- دالة عرض الصورة بحجم كامل ---
  void _showFullImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: Image.network(imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity),
            ),
            Positioned(
              top: 30,
              right: 30,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- دالة حذف الصورة للمالك ---
  void _confirmRemoveImage(ProjectModel project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الصورة', style: TextStyle(color: Colors.red)),
        content: const Text('هل أنت متأكد من حذف صورة هذا المشروع؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              setState(() => project.imageUrl = null);
              await ProjectManager.saveProjectsToCloud(_projects);
              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف الصورة بنجاح')));
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _pickAndUploadImage(ProjectModel project) async {
    final supabase = Supabase.instance.client;
    final picker = ImagePicker();
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرفاق صورة للمشروع'),
        actions: [
          TextButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('المعرض'),
              onPressed: () => Navigator.pop(context, ImageSource.gallery)),
          TextButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('الكاميرا'),
              onPressed: () => Navigator.pop(context, ImageSource.camera)),
        ],
      ),
    );
    if (source == null) return;

    final XFile? image =
        await picker.pickImage(source: source, imageQuality: 70);
    if (image != null) {
      setState(() => _isLoadingImage = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('جاري الرفع للسحابة...')));
      try {
        final bytes = await image.readAsBytes();
        final fileExt = image.name.split('.').last;
        final fileName =
            'project_${project.projectId}_${const Uuid().v4()}.$fileExt';

        await supabase.storage.from('alrozana-images').uploadBinary(
            fileName, bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true));
        final String publicUrl =
            supabase.storage.from('alrozana-images').getPublicUrl(fileName);

        setState(() => project.imageUrl = publicUrl);
        await ProjectManager.saveProjectsToCloud(_projects);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم إرفاق الصورة بنجاح!'),
              backgroundColor: Colors.green));
      } catch (e) {
        debugPrint('خطأ رفع الصورة: $e');
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('فشل الرفع: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoadingImage = false);
      }
    }
  }

  void _showPaymentsDialog(ProjectModel project) {
    final amountController = TextEditingController();
    String todayDate = DateTime.now().toString().substring(0, 10);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('سجل الدفعات: ${project.clientName}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('المتبقي: ${formatMoney(project.remainingAmount)}',
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                      Text('المدفوع: ${formatMoney(project.totalPaid)}',
                          style: const TextStyle(
                              color: Colors.green, fontWeight: FontWeight.bold))
                    ]),
                const Divider(),
                if (project.payments.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('لا توجد دفعات مسجلة حتى الآن.')),
                if (project.payments.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: project.payments.length,
                      itemBuilder: (context, index) {
                        final p = project.payments[index];
                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.attach_money,
                                color: Colors.green),
                            title: Text(formatMoney(p.amount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(p.date,
                                style: const TextStyle(fontSize: 11)),
                            trailing: widget.isOwner
                                ? IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red, size: 20),
                                    onPressed: () async {
                                      setDialogState(() =>
                                          project.payments.removeAt(index));
                                      setState(() {});
                                      await ProjectManager.saveProjectsToCloud(
                                          _projects);
                                    })
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                const Divider(),
                if (widget.isOwner)
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                              controller: amountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'مبلغ الدفعة',
                                  border: OutlineInputBorder(),
                                  isDense: true))),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white),
                        onPressed: () async {
                          double? val = double.tryParse(amountController.text);
                          if (val != null && val > 0) {
                            if (val > project.remainingAmount) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'المبلغ أكبر من الرصيد المتبقي!'),
                                      backgroundColor: Colors.red));
                              return;
                            }
                            setDialogState(() {
                              project.payments.add(
                                  PaymentRecord(amount: val, date: todayDate));
                              amountController.clear();
                            });
                            setState(() {});
                            await ProjectManager.saveProjectsToCloud(_projects);
                          }
                        },
                      )
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'))
          ],
        ),
      ),
    );
  }

  Widget _buildProjectsArea() {
    if (_isGroupedByClient) {
      Map<String, List<ProjectModel>> groupedProjects = {};
      for (var p in sortedProjects) {
        groupedProjects.putIfAbsent(p.clientName, () => []).add(p);
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groupedProjects.keys.length,
        itemBuilder: (context, index) {
          String client = groupedProjects.keys.elementAt(index);
          List<ProjectModel> clientProjects = groupedProjects[client]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.3))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Icon(Icons.person,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20),
                      const SizedBox(width: 8),
                      Text('العميل: $client',
                          style: TextStyle(
                              fontSize: AppSettings.baseFontSize + 1,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary))
                    ]),
                    Row(children: [
                      Text('(${clientProjects.length} مشاريع)',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      const SizedBox(width: 10),
                      IconButton(
                          icon: const Icon(Icons.print,
                              size: 20, color: Colors.brown),
                          onPressed: () =>
                              DashboardScreen.generatePdfReportStatic(
                                  context,
                                  'تقرير مشاريع العميل: $client',
                                  clientProjects),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints())
                    ]),
                  ],
                ),
              ),
              _isGridView
                  ? LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: clientProjects
                              .map((p) => SizedBox(
                                  width: (constraints.maxWidth - 12) / 2,
                                  child: _buildProjectCard(p, isGrid: true)))
                              .toList()))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: clientProjects.length,
                      itemBuilder: (context, idx) => _buildProjectCard(
                          clientProjects[idx],
                          isGrid: false)),
            ],
          );
        },
      );
    } else {
      return _isGridView
          ? SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: sortedProjects
                          .map((p) => SizedBox(
                              width: (constraints.maxWidth - 12) / 2,
                              child: _buildProjectCard(p, isGrid: true)))
                          .toList())))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: sortedProjects.length,
              itemBuilder: (context, index) =>
                  _buildProjectCard(sortedProjects[index], isGrid: false));
    }
  }

  Widget _buildAnimatedMargin(Color glowColor) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        double yPos = -2.0 + (_glowController.value * 4);
        return Container(
            width: 6,
            decoration: BoxDecoration(
                color: glowColor.withOpacity(0.02),
                gradient: LinearGradient(
                    begin: Alignment(0, yPos - 0.5),
                    end: Alignment(0, yPos + 0.5),
                    colors: [
                      glowColor.withOpacity(0.0),
                      glowColor.withOpacity(1.0),
                      glowColor.withOpacity(0.0)
                    ],
                    stops: const [
                      0.0,
                      0.5,
                      1.0
                    ])));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalContractsAll =
        _projects.fold(0.0, (sum, p) => sum + p.contractValue);
    double totalRemainingAll =
        _projects.fold(0.0, (sum, p) => sum + p.remainingAmount);
    int activeProjectsCount = _projects.where((p) => p.progress < 1.0).length;
    int completedProjectsCount =
        _projects.where((p) => p.progress >= 1.0).length;
    Color currentPrimary = Theme.of(context).colorScheme.primary;

    Widget mainDashboardContent = Column(
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              if (_isLoadingImage)
                const LinearProgressIndicator(color: Colors.green),
              Row(children: [
                Expanded(
                    child: _buildStatCard(
                        'إجمالي العقود',
                        formatMoney(totalContractsAll),
                        Icons.request_quote,
                        Colors.green)),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildStatCard(
                        'إجمالي المتبقي',
                        formatMoney(totalRemainingAll),
                        Icons.account_balance,
                        Colors.red))
              ]),
              const SizedBox(height: 5),
              Row(children: [
                Expanded(
                    child: _buildStatCard('المشاريع النشطة',
                        '$activeProjectsCount', Icons.handyman, Colors.green)),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildStatCard('المشاريع المنتهية',
                        '$completedProjectsCount', Icons.verified, Colors.red))
              ]),
              const SizedBox(height: 10),
              SizedBox(
                  height: 40,
                  child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                          hintText: 'ابحث...',
                          prefixIcon: Icon(Icons.search,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20),
                          filled: true,
                          isDense: true,
                          fillColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey[800]
                                  : Colors.white,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8))))),
            ],
          ),
        ),
        const Divider(height: 15),
        Expanded(child: _buildProjectsArea()),
        Container(
            padding: const EdgeInsets.all(5),
            width: double.infinity,
            color: Colors.brown.withOpacity(0.1),
            child: Text(AppSettings.footerMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.brown,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    fontFamily: AppSettings.fontFamily)))
      ],
    );

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70.0),
        child: AppBar(
          toolbarHeight: 70.0,
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Image.asset('assets/images/logo.png',
                  width: 45, height: 45, fit: BoxFit.contain),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppSettings.appTitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: AppSettings.fontFamily,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(_isGroupedByClient ? Icons.layers_clear : Icons.layers,
                  size: 20),
              tooltip: 'تجميع حسب العميل',
              onPressed: () =>
                  setState(() => _isGroupedByClient = !_isGroupedByClient),
            ),
            IconButton(
              icon: const Icon(Icons.brightness_6, size: 20),
              tooltip: 'تغيير المظهر',
              onPressed: () => AlrozanaApp.switchTheme(context),
            ),
            IconButton(
              icon: Icon(_isGridView ? Icons.list : Icons.grid_view, size: 20),
              tooltip: 'تغيير العرض',
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),
            if (widget.isOwner)
              IconButton(
                  icon: const Icon(Icons.settings, size: 20),
                  tooltip: 'الإعدادات',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                              onSettingsSaved: () => setState(() {}),
                              allProjects: _projects)))),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
              tooltip: 'خروج',
              onPressed: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const PinLoginScreen())),
            ),
          ],
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAnimatedMargin(currentPrimary),
          Expanded(child: mainDashboardContent),
          _buildAnimatedMargin(currentPrimary),
        ],
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton(
              onPressed: () => _showProjectDialog(),
              child: const Icon(Icons.add))
          : null,
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
        elevation: 1,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: Column(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 2),
              Text(title,
                  style: TextStyle(
                      fontFamily: AppSettings.fontFamily, fontSize: 11)),
              Text(value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontFamily: AppSettings.fontFamily))
            ])));
  }

  Widget _buildProjectCard(ProjectModel project, {required bool isGrid}) {
    Color primary = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: project.progress >= 1.0 ? 0 : 3,
      margin: EdgeInsets.only(bottom: isGrid ? 0 : 15),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(project.projectNumber,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: primary,
                                fontSize: 13)),
                        backgroundColor: primary.withOpacity(0.1)),
                    const SizedBox(width: 5),
                    IconButton(
                        icon: const Icon(Icons.print,
                            size: 18, color: Colors.brown),
                        onPressed: () =>
                            DashboardScreen.generatePdfReportStatic(
                                context,
                                'تقرير المشروع: ${project.projectNumber}',
                                [project]),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints()),
                    const SizedBox(width: 5),
                    IconButton(
                        icon: const Icon(Icons.account_balance_wallet,
                            size: 18, color: Colors.green),
                        onPressed: () => _showPaymentsDialog(project),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints()),

                    // --- إخفاء زر الكاميرا عن الموظفين وإظهاره للمالك فقط ---
                    if (widget.isOwner) ...[
                      const SizedBox(width: 5),
                      IconButton(
                        icon: const Icon(Icons.add_a_photo,
                            size: 18, color: Colors.blueAccent),
                        onPressed: () => _pickAndUploadImage(project),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ],
                ),
                if (widget.isOwner)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        icon: const Icon(Icons.edit,
                            size: 20, color: Colors.blue),
                        onPressed: () =>
                            _showProjectDialog(projectToEdit: project),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints()),
                    const SizedBox(width: 10),
                    IconButton(
                        icon: const Icon(Icons.delete,
                            size: 20, color: Colors.red),
                        onPressed: () => _confirmDeleteProject(project),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints())
                  ])
                else
                  Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(project.status,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
                      backgroundColor: project.progressColor),
              ],
            ),
            const SizedBox(height: 5),
            Text(project.clientName,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppSettings.baseFontSize + 2)),

            // --- عرض الصورة مع إمكانية فتحها بحجم كامل + زر الحذف للمالك ---
            if (project.imageUrl != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _showFullImage(project.imageUrl!),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          project.imageUrl!,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                  color: Colors.grey[300],
                                  height: 120,
                                  child: const Center(
                                      child: Icon(Icons.broken_image,
                                          color: Colors.red))),
                          loadingBuilder: (context, child, loadingProgress) =>
                              loadingProgress == null
                                  ? child
                                  : Container(
                                      height: 120,
                                      color: Colors.grey[100],
                                      child: const Center(
                                          child: CircularProgressIndicator())),
                        ),
                      ),
                    ),
                    if (widget.isOwner)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: CircleAvatar(
                          backgroundColor: Colors.red.withOpacity(0.85),
                          radius: 14,
                          child: IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.white, size: 14),
                            onPressed: () => _confirmRemoveImage(project),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'حذف الصورة',
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('العقد: ${formatMoney(project.contractValue)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12)),
              Text('المدفوع: ${formatMoney(project.totalPaid)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 12))
            ]),
            const SizedBox(height: 10),
            if (isGrid) ...[
              Center(
                  child: SizedBox(
                      width: 70,
                      height: 70,
                      child: Stack(fit: StackFit.expand, children: [
                        CircularProgressIndicator(
                            value: project.progress,
                            strokeWidth: 8,
                            backgroundColor: Colors.grey[300],
                            color: project.progressColor),
                        Center(
                            child: Text('${(project.progress * 100).toInt()}%',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: project.progressColor)))
                      ]))),
              const SizedBox(height: 10),
            ] else ...[
              LinearProgressIndicator(
                  value: project.progress,
                  color: project.progressColor,
                  backgroundColor: Colors.grey[300],
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(5)),
              const SizedBox(height: 10),
            ],
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('المتبقي:',
                  style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
              Text(formatMoney(project.remainingAmount),
                  style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: AppSettings.baseFontSize + 1))
            ]),
            if (project.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.edit_note, size: 16, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                    child: Text('ملاحظات: ${project.notes}',
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                            fontSize: AppSettings.baseFontSize - 2)))
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
