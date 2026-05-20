import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/modern_background.dart';

/// Amethyst / mint / cyan — matches Kidora theme.
const List<Color> _kInsightColors = [
  Color(0xFF9C27B0),
  Color(0xFFBA68C8),
  Color(0xFF69F0AE),
  Color(0xFF00E5FF),
  Color(0xFF7C4DFF),
  Color(0xFFFFB74D),
  Color(0xFF64B5F6),
];

/// Sri Lankan professionals listed on [kDocLkUrl] for optional family support.
const String kDocLkUrl = 'https://www.doc.lk/';

const List<Map<String, String>> _kDocLkCounselors = [
  {
    'name': 'Dr. Kalharie Pitigala',
    'focus':
        'Counselling psychologist · Child & adolescent psychologist · Psychologist',
  },
  {
    'name': 'Dr. Chandana Waidyasekara',
    'focus':
        'Counselling psychologist · Clinical hypnotist · Psychotherapist',
  },
  {
    'name': 'Ms. Samanthi Weerasekara',
    'focus': 'Psychological counselling · Counselling psychologist',
  },
  {
    'name': 'Ms. Iresha Kariyawasam',
    'focus':
        'Psychotherapist · Family & couple counselling · Trauma-informed care',
  },
];

class WeeklyInsightsScreen extends StatefulWidget {
  final Map<String, dynamic> child;
  const WeeklyInsightsScreen({super.key, required this.child});

  @override
  State<WeeklyInsightsScreen> createState() => _WeeklyInsightsScreenState();
}

class _WeeklyInsightsScreenState extends State<WeeklyInsightsScreen> {
  final GlobalKey _weeklyBarKey = GlobalKey();
  final GlobalKey _pieKey = GlobalKey();

  bool isLoading = true;
  bool _exporting = false;
  List<dynamic> weeklyData = [];
  Map<String, dynamic> todayUsage = {'total_screen_time': 0, 'apps': []};
  /// Per-app durations summed over the same window as [weeklyData] (default 7 days).
  Map<String, dynamic> weeklyAppsUsage = {'total_screen_time': 0, 'apps': []};
  List<Map<String, dynamic>> _preparedWeek = [];

  @override
  void initState() {
    super.initState();
    _fetchWeeklyData();
  }

  void _prepareWeekData() {
    final list = <Map<String, dynamic>>[];
    final today = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final dayName = DateFormat('EEE').format(date);
      double duration = 0;
      for (final element in weeklyData) {
        if (element['date'].toString().startsWith(dateStr)) {
          duration = double.tryParse(element['total_duration'].toString()) ?? 0;
          break;
        }
      }
      list.add({'day': dayName, 'date': dateStr, 'duration': duration});
    }
    _preparedWeek = list;
  }

  Future<void> _fetchWeeklyData() async {
    setState(() => isLoading = true);
    try {
      final weekly = await ApiService.getWeeklyUsageSummary(widget.child['id']);
      final today = await ApiService.getTodayUsageSummary(widget.child['id']);
      final weeklyApps = await ApiService.getWeeklyAppsUsageSummary(widget.child['id']);
      weeklyData = weekly;
      todayUsage = today;
      weeklyAppsUsage = weeklyApps;
      _prepareWeekData();
    } catch (e) {
      debugPrint("Error fetching data: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  double _maxWeekDuration() {
    if (_preparedWeek.isEmpty) return 3600;
    final m = _preparedWeek
        .map((e) => (e['duration'] as num).toDouble())
        .fold<double>(0, (a, b) => b > a ? b : a);
    return m < 600 ? 3600 : m * 1.12;
  }

  double _pieChartTotalSeconds(List<dynamic> apps, Map<String, dynamic> usage) {
    final api = (usage['total_screen_time'] as num?)?.toDouble() ?? 0;
    double sum = 0;
    for (final a in apps) {
      sum += (a['duration'] as num?)?.toDouble() ?? 0;
    }
    if (api > 0) return api;
    if (sum > 0) return sum;
    return 1;
  }

  double _todayScreenSeconds() {
    return (todayUsage['total_screen_time'] as num?)?.toDouble() ?? 0;
  }

  double _weeklyAverageDailySeconds() {
    if (_preparedWeek.isEmpty) return 0;
    final sum = _preparedWeek.fold<double>(
      0,
      (a, d) => a + (d['duration'] as num).toDouble(),
    );
    return sum / 7.0;
  }

  double _weeklyMaxDaySeconds() {
    if (_preparedWeek.isEmpty) return 0;
    return _preparedWeek
        .map((d) => (d['duration'] as num).toDouble())
        .fold<double>(0, (a, b) => b > a ? b : a);
  }

  bool _nameMatchesVideoSocial(String appNameLower, String packageLower) {
    final combined = '$appNameLower $packageLower';
    return combined.contains('youtube') ||
        combined.contains('tiktok') ||
        combined.contains('shorts');
  }

  bool _hasHeavyVideoSocialAppToday() {
    final apps = (todayUsage['apps'] as List?) ?? [];
    for (final app in apps) {
      final name = '${app['app_name'] ?? ''}'.toLowerCase();
      final pkg = '${app['package_name'] ?? ''}'.toLowerCase();
      final mins = ((app['duration'] as num?)?.toDouble() ?? 0) / 60.0;
      if (_nameMatchesVideoSocial(name, pkg) && mins > 45) return true;
    }
    return false;
  }

  /// Same pattern as daily check: 3+ hours on one short-form / video app across the week.
  bool _hasHeavyVideoSocialWeekly() {
    final apps = (weeklyAppsUsage['apps'] as List?) ?? [];
    for (final app in apps) {
      final name = '${app['app_name'] ?? ''}'.toLowerCase();
      final pkg = '${app['package_name'] ?? ''}'.toLowerCase();
      final mins = ((app['duration'] as num?)?.toDouble() ?? 0) / 60.0;
      if (_nameMatchesVideoSocial(name, pkg) && mins >= 180) return true;
    }
    return false;
  }

  /// Patterns that suggest extra support for healthier digital habits (non-diagnostic).
  bool _shouldSuggestCounselor() {
    if (_todayScreenSeconds() >= 3 * 3600) return true;
    if (_weeklyAverageDailySeconds() >= 2.5 * 3600) return true;
    if (_weeklyMaxDaySeconds() >= 4 * 3600) return true;
    return _hasHeavyVideoSocialAppToday() || _hasHeavyVideoSocialWeekly();
  }

  Map<String, String> _counselorPickedThisWeek() {
    final rawId = widget.child['id'];
    final idPart = rawId is int ? rawId : rawId.hashCode;
    final weekBucket = DateTime.now().millisecondsSinceEpoch ~/
        (7 * 24 * 60 * 60 * 1000);
    final i = (idPart.abs() + weekBucket) % _kDocLkCounselors.length;
    return _kDocLkCounselors[i];
  }

  Future<void> _openDocLk() async {
    if (!Platform.isAndroid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Open in your browser: $kDocLkUrl'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      await AndroidIntent(
        action: 'action_view',
        data: kDocLkUrl,
      ).launch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open browser: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<Uint8List?> _capturePng(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Chart capture failed: $e');
      return null;
    }
  }

  Future<pw.Document> _buildPdfDocument(
    Uint8List? weeklyBarPng,
    Uint8List? piePng,
  ) async {
    final doc = pw.Document();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final childName = '${widget.child['name'] ?? 'Child'}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          final blocks = <pw.Widget>[
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 16),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.purple700, width: 2),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Kidora — Weekly screen time insight',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.purple900,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Child: $childName   ·   Generated: $todayStr',
                    style: const pw.TextStyle(
                      fontSize: 11,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              '1. Last 7 days (screen time trend)',
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.purple800,
              ),
            ),
            pw.SizedBox(height: 10),
          ];

          if (weeklyBarPng != null) {
            blocks.add(
              pw.Center(
                child: pw.Image(
                  pw.MemoryImage(weeklyBarPng),
                  width: 480,
                  fit: pw.BoxFit.contain,
                ),
              ),
            );
            blocks.add(pw.SizedBox(height: 16));
          }

          blocks.addAll([
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.purple50),
                  children: [
                    _pdfCell('Day', bold: true),
                    _pdfCell('Date', bold: true),
                    _pdfCell('Screen time', bold: true),
                  ],
                ),
                ..._preparedWeek.map(
                  (d) => pw.TableRow(
                    children: [
                      _pdfCell(d['day'] as String),
                      _pdfCell(d['date'] as String),
                      _pdfCell(_formatDuration((d['duration'] as num).toDouble())),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 28),
            pw.Text(
              '2. Weekly app mix (last 7 days, pie chart)',
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.purple800,
              ),
            ),
            pw.SizedBox(height: 10),
          ]);

          if (piePng != null) {
            blocks.add(
              pw.Center(
                child: pw.Image(
                  pw.MemoryImage(piePng),
                  width: 420,
                  fit: pw.BoxFit.contain,
                ),
              ),
            );
            blocks.add(pw.SizedBox(height: 16));
          }

          final apps = (weeklyAppsUsage['apps'] as List?) ?? [];
          if (apps.isNotEmpty) {
            blocks.addAll([
              pw.Text(
                'Top apps (7-day total)',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 8),
              ...apps.take(10).map<pw.Widget>(
                (app) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${app['app_name'] ?? app['package_name'] ?? 'App'}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                      pw.Text(
                        _formatDuration(
                          (app['duration'] as num?)?.toDouble() ?? 0,
                        ),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]);
          }

          blocks.addAll([
            pw.SizedBox(height: 24),
            pw.Text(
              '3. Recommendations',
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.purple800,
              ),
            ),
            pw.SizedBox(height: 8),
            ..._pdfRecommendationBullets(),
            ..._pdfCounselorSection(),
            pw.SizedBox(height: 32),
            pw.Divider(color: PdfColors.grey300),
            pw.Center(
              child: pw.Text(
                'Generated by Kidora · Confidential family report',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
              ),
            ),
          ]);

          return blocks;
        },
      ),
    );
    return doc;
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  List<pw.Widget> _pdfRecommendationBullets() {
    final totalMins = (todayUsage['total_screen_time'] as num?)?.toDouble() ?? 0;
    final totalM = totalMins / 60.0;
    final apps = (todayUsage['apps'] as List?) ?? [];
    final lines = <String>[];

    if (totalM > 180) {
      lines.add(
        'Higher overall screen time today (${totalM.toStringAsFixed(0)} min). Consider a calmer evening routine.',
      );
    } else if (totalM > 0 && totalM < 60) {
      lines.add('Total usage is moderate today — good balance for school nights.');
    }

    for (final app in apps) {
      final name = '${app['app_name'] ?? ''}'.toLowerCase();
      final mins = ((app['duration'] as num?)?.toDouble() ?? 0) / 60.0;
      if ((name.contains('youtube') ||
              name.contains('tiktok') ||
              name.contains('shorts')) &&
          mins > 45) {
        lines.add(
          'Notable video / short-form time on ${app['app_name']} (${mins.toStringAsFixed(0)} min). Mix in offline activities.',
        );
      }
    }

    if (lines.isEmpty) {
      lines.add(
        'No strong risk flags from this week’s pattern. Continue gentle check-ins with your child.',
      );
    }

    return lines
        .map(
          (t) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 6,
                  height: 6,
                  margin: const pw.EdgeInsets.only(top: 3, right: 8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.deepPurple,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(child: pw.Text(t, style: const pw.TextStyle(fontSize: 10))),
              ],
            ),
          ),
        )
        .toList();
  }

  List<pw.Widget> _pdfCounselorSection() {
    if (!_shouldSuggestCounselor()) return [];

    final c = _counselorPickedThisWeek();
    return [
      pw.SizedBox(height: 20),
      pw.Text(
        '4. Optional: professional support (Sri Lanka)',
        style: pw.TextStyle(
          fontSize: 15,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.purple800,
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'This week’s screen time pattern suggests extra support could help build healthier digital habits. '
        'This is general guidance, not a diagnosis. One counsellor you may consider:',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800, lineSpacing: 1.3),
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.purple50,
          border: pw.Border.all(color: PdfColors.purple200),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              c['name']!,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.purple900,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              c['focus']!,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800, lineSpacing: 1.25),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 10),
      pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
          children: [
            const pw.TextSpan(text: 'Book an appointment online: '),
            pw.TextSpan(
              text: kDocLkUrl,
              style: const pw.TextStyle(
                color: PdfColors.blue,
                decoration: pw.TextDecoration.underline,
              ),
              annotation: pw.AnnotationUrl(kDocLkUrl),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _exportToPDF() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    await Future.delayed(const Duration(milliseconds: 200));

    Uint8List? barPng;
    Uint8List? piePng;
    try {
      barPng = await _capturePng(_weeklyBarKey);
      piePng = await _capturePng(_pieKey);
    } catch (_) {}

    try {
      final doc = await _buildPdfDocument(barPng, piePng);
      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'Kidora_Weekly_${widget.child['name'] ?? 'Child'}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF ready — use Save or Drive from the share sheet.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create PDF: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _formatDuration(double seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${seconds.round()}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleStyle = GoogleFonts.outfit(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
      letterSpacing: 0.3,
    );
    final headingStyle = GoogleFonts.outfit(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: isDark ? Colors.white : AppTheme.lightTextPrimary,
    );

    final maxY = _maxWeekDuration();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Weekly insights',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
      ),
      body: ModernBackground(
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.child['name'] != null
                            ? '${widget.child['name']} · last 7 days'
                            : 'Last 7 days',
                        style: titleStyle,
                      ),
                      const SizedBox(height: 6),
                      Text('Screen time trend', style: headingStyle),
                      const SizedBox(height: 16),
                      GlassCard(
                        borderRadius: 24,
                        padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
                        child: RepaintBoundary(
                          key: _weeklyBarKey,
                          child: SizedBox(
                            height: 280,
                            child: _preparedWeek.isEmpty
                                ? Center(
                                    child: Text(
                                      'No weekly data yet',
                                      style: titleStyle,
                                    ),
                                  )
                                : BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY: maxY,
                                      minY: 0,
                                      groupsSpace: 10,
                                      barTouchData: BarTouchData(
                                        enabled: true,
                                        touchTooltipData: BarTouchTooltipData(
                                          getTooltipColor: (_) =>
                                              AppTheme.primaryColorDark.withValues(alpha: 0.95),
                                          tooltipPadding:
                                              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          tooltipMargin: 8,
                                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                            final d = _preparedWeek[group.x.toInt()];
                                            final sec = (d['duration'] as num).toDouble();
                                            return BarTooltipItem(
                                              '${d['day']}\n${_formatDuration(sec)}',
                                              GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      titlesData: FlTitlesData(
                                        show: true,
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 44,
                                            interval: maxY > 7200 ? 3600 : 1800,
                                            getTitlesWidget: (v, m) {
                                              if (v < 0) return const SizedBox.shrink();
                                              final h = (v / 3600).floor();
                                              final min = ((v % 3600) / 60).round();
                                              final label = h > 0 ? '${h}h' : '${min}m';
                                              return Padding(
                                                padding: const EdgeInsets.only(right: 6),
                                                child: Text(
                                                  label,
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 10,
                                                    color: isDark
                                                        ? Colors.white54
                                                        : AppTheme.lightTextSecondary,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (v, m) {
                                              final i = v.toInt();
                                              if (i < 0 || i >= _preparedWeek.length) {
                                                return const SizedBox.shrink();
                                              }
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 8),
                                                child: Text(
                                                  _preparedWeek[i]['day'] as String,
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: isDark
                                                        ? Colors.white70
                                                        : AppTheme.lightTextPrimary,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                        horizontalInterval: maxY > 7200 ? 3600 : 1800,
                                        getDrawingHorizontalLine: (v) => FlLine(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.08)
                                              : AppTheme.lightBorder.withValues(alpha: 0.6),
                                          strokeWidth: 1,
                                        ),
                                      ),
                                      borderData: FlBorderData(
                                        show: true,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: isDark
                                                ? Colors.white24
                                                : AppTheme.lightBorder,
                                          ),
                                          left: BorderSide(
                                            color: isDark
                                                ? Colors.white24
                                                : AppTheme.lightBorder,
                                          ),
                                        ),
                                      ),
                                      barGroups: List.generate(_preparedWeek.length, (i) {
                                        final sec =
                                            (_preparedWeek[i]['duration'] as num).toDouble();
                                        return BarChartGroupData(
                                          x: i,
                                          barsSpace: 4,
                                          barRods: [
                                            BarChartRodData(
                                              toY: sec.clamp(0, maxY),
                                              width: 18,
                                              borderRadius: const BorderRadius.vertical(
                                                top: Radius.circular(8),
                                              ),
                                              gradient: LinearGradient(
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: [
                                                  AppTheme.primaryColor.withValues(alpha: 0.85),
                                                  AppTheme.accentColor,
                                                ],
                                              ),
                                              backDrawRodData: BackgroundBarChartRodData(
                                                show: true,
                                                toY: maxY,
                                                color: isDark
                                                    ? Colors.white.withValues(alpha: 0.06)
                                                    : AppTheme.lightPrimaryColor.withValues(alpha: 0.12),
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text('This week’s app mix', style: headingStyle),
                      const SizedBox(height: 8),
                      Text(
                        'Share of screen time by app over the last 7 days (top categories)',
                        style: titleStyle,
                      ),
                      const SizedBox(height: 16),
                      _buildWeeklyAppMixBreakdown(isDark),
                      const SizedBox(height: 28),
                      Text('Suggestions', style: headingStyle),
                      const SizedBox(height: 12),
                      _buildRecommendationsSection(isDark),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: _exporting ? null : _exportToPDF,
                          icon: _exporting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(
                            _exporting ? 'Preparing PDF…' : 'Download PDF report',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildWeeklyAppMixBreakdown(bool isDark) {
    final List<dynamic> apps = weeklyAppsUsage['apps'] ?? [];
    if (apps.isEmpty) {
      return GlassCard(
        borderRadius: 24,
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No per-app usage recorded for the last 7 days yet.',
            style: GoogleFonts.outfit(
              color: isDark ? Colors.white60 : AppTheme.lightTextSecondary,
            ),
          ),
        ),
      );
    }

    final totalSecs = _pieChartTotalSeconds(apps, weeklyAppsUsage);
    final sliceCount = apps.length > 6 ? 6 : apps.length;

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth > 420;
          final pie = RepaintBoundary(
            key: _pieKey,
            child: SizedBox(
              height: wide ? 260 : 240,
              width: wide ? 260 : double.infinity,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: wide ? 52 : 44,
                  centerSpaceColor: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : AppTheme.lightBackground,
                  sections: List.generate(sliceCount, (i) {
                    final app = apps[i];
                    final duration = (app['duration'] as num).toDouble();
                    final pct = (duration / totalSecs) * 100;
                    final color = _kInsightColors[i % _kInsightColors.length];
                    return PieChartSectionData(
                      color: color,
                      value: duration,
                      title: pct >= 6 ? '${pct.toStringAsFixed(0)}%' : '',
                      radius: wide ? 62 : 54,
                      titleStyle: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                      titlePositionPercentageOffset: 0.58,
                      borderSide: BorderSide(
                        color: isDark ? Colors.white12 : Colors.white,
                        width: 2,
                      ),
                    );
                  }),
                ),
              ),
            ),
          );

          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(sliceCount, (i) {
              final app = apps[i];
              final duration = (app['duration'] as num).toDouble();
              final pct = (duration / totalSecs) * 100;
              final color = _kInsightColors[i % _kInsightColors.length];
              final name = '${app['app_name'] ?? app['package_name'] ?? 'App'}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.45),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${pct.toStringAsFixed(0)}% · ${_formatDuration(duration)}',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white60 : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          );

          if (!wide) {
            return Column(
              children: [
                pie,
                const SizedBox(height: 20),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              pie,
              const SizedBox(width: 20),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRecommendationsSection(bool isDark) {
    final totalMins =
        ((todayUsage['total_screen_time'] as num?)?.toDouble() ?? 0) / 60.0;
    final List<dynamic> apps = todayUsage['apps'] ?? [];
    final recs = <Widget>[];

    if (totalMins > 180) {
      recs.add(_recommendationItem(
        isDark,
        Icons.schedule_rounded,
        AppTheme.errorColor.withValues(alpha: 0.9),
        'Higher usage today',
        'About ${totalMins.round()} minutes total. A wind-down routine before bed often helps sleep.',
      ));
    } else if (totalMins > 0 && totalMins < 60) {
      recs.add(_recommendationItem(
        isDark,
        Icons.eco_rounded,
        AppTheme.darkPrimaryColor,
        'Balanced day',
        'Total screen time is under an hour — great for school nights.',
      ));
    }

    for (final app in apps) {
      final name = '${app['app_name'] ?? ''}'.toLowerCase();
      final mins = ((app['duration'] as num?)?.toDouble() ?? 0) / 60.0;
      if ((name.contains('youtube') ||
              name.contains('tiktok') ||
              name.contains('shorts')) &&
          mins > 45) {
        recs.add(_recommendationItem(
          isDark,
          Icons.video_library_rounded,
          AppTheme.accentColor,
          'Video & short-form',
          '${mins.round()} min on ${app['app_name']}. Mix in offline hobbies or reading.',
        ));
      }
    }

    if (recs.isEmpty) {
      recs.add(_recommendationItem(
        isDark,
        Icons.insights_rounded,
        AppTheme.primaryColorLight,
        'All clear',
        'No strong flags from this snapshot. Keep having light conversations about online time.',
      ));
    }

    if (_shouldSuggestCounselor()) {
      recs.add(_counselorSupportCard(isDark));
    }

    return Column(children: recs);
  }

  Widget _counselorSupportCard(bool isDark) {
    final c = _counselorPickedThisWeek();
    final accent = AppTheme.primaryColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.18 : 0.10),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.psychology_rounded, color: accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Consider professional support',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'This week’s pattern suggests a counsellor could help your child build healthier digital habits. '
                          'This is general guidance, not medical advice. One Sri Lanka–based profile to explore:',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            height: 1.35,
                            color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                c['name']!,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c['focus']!,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  height: 1.3,
                  color: isDark ? Colors.white60 : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _openDocLk,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: isDark ? 0.28 : 0.18),
                    foregroundColor: isDark ? Colors.white : AppTheme.lightTextPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Open doc.lk to book',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recommendationItem(
    bool isDark,
    IconData icon,
    Color accent,
    String title,
    String body,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.14 : 0.08),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        height: 1.35,
                        color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
