/// 数据模型（PLAN.md §4.3 / §4.4），JSON 读写都在这里。
library;

import 'chapter_numbering.dart';

/// 卷级章节编号模式（两层编号的卷层）。
///
/// - [followGlobal] 跟随全局编号：全局配置开启时按全局规则编号，关闭则不编号；
/// - [independent] 卷内独立编号：使用本卷自己的规则（[Volume.numbering]）；
/// - [none] 不编号。
enum VolumeNumberingMode {
  followGlobal('follow-global'),
  independent('independent'),
  none('none');

  const VolumeNumberingMode(this.code);

  /// JSON 持久化用编码；未知编码回退 [followGlobal]。
  final String code;

  /// 解析持久化编码；未知或非字符串返回 `null`（交给迁移逻辑推导）。
  static VolumeNumberingMode? tryFromCode(Object? code) => switch (code) {
    'independent' => VolumeNumberingMode.independent,
    'none' => VolumeNumberingMode.none,
    'follow-global' => VolumeNumberingMode.followGlobal,
    _ => null,
  };

  static VolumeNumberingMode fromCode(String? code) =>
      tryFromCode(code) ?? VolumeNumberingMode.followGlobal;
}

class LibraryIndex {
  LibraryIndex({this.schemaVersion = 1, List<BookSummary>? books})
    : books = books ?? <BookSummary>[];

  int schemaVersion;
  final List<BookSummary> books;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'books': books.map((BookSummary b) => b.toJson()).toList(),
  };

  static LibraryIndex fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = (json['books'] as List<dynamic>? ?? <dynamic>[]);
    return LibraryIndex(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      books: raw
          .whereType<Map<String, dynamic>>()
          .map(BookSummary.fromJson)
          .toList(),
    );
  }
}

class BookSummary {
  BookSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.coverSeed,
    this.lastOpenedChapterId,
    this.volumeCount = 0,
    this.chapterCount = 0,
    this.wordCount = 0,
  });

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  final int coverSeed;
  String? lastOpenedChapterId;
  int volumeCount;
  int chapterCount;
  int wordCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'coverSeed': coverSeed,
    'lastOpenedChapterId': lastOpenedChapterId,
    'volumeCount': volumeCount,
    'chapterCount': chapterCount,
    'wordCount': wordCount,
  };

  static BookSummary fromJson(Map<String, dynamic> json) => BookSummary(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '未命名作品',
    createdAt: _parseDate(json['createdAt']),
    updatedAt: _parseDate(json['updatedAt']),
    coverSeed: (json['coverSeed'] as num?)?.toInt() ?? 0,
    lastOpenedChapterId: json['lastOpenedChapterId'] as String?,
    volumeCount: (json['volumeCount'] as num?)?.toInt() ?? 0,
    chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
  );
}

class BookIndex {
  BookIndex({
    this.schemaVersion = 1,
    required this.id,
    required this.title,
    this.notes = '',
    this.globalNumbering = const ChapterNumbering(),
    List<Volume>? volumes,
  }) : volumes = volumes ?? <Volume>[];

  int schemaVersion;
  final String id;
  String title;
  String notes;

  /// 书籍级「全局自动章节序号」配置（默认关闭）。
  ///
  /// 仅对编号模式为 [VolumeNumberingMode.followGlobal] 的卷生效；
  /// 关闭时这些卷不编号。规则字段与卷级规则一致（[ChapterNumbering]）。
  ChapterNumbering globalNumbering;
  final List<Volume> volumes;

  Iterable<ChapterMeta> get allChapters =>
      volumes.expand((Volume v) => v.chapters);

  int get totalWordCount =>
      volumes.fold(0, (int sum, Volume v) => sum + v.wordCount);

  Volume? volumeOfChapter(String chapterId) {
    for (final Volume v in volumes) {
      if (v.chapters.any((ChapterMeta c) => c.id == chapterId)) return v;
    }
    return null;
  }

  ChapterMeta? chapterById(String chapterId) {
    for (final Volume v in volumes) {
      for (final ChapterMeta c in v.chapters) {
        if (c.id == chapterId) return c;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'id': id,
    'title': title,
    'notes': notes,
    'globalNumbering': globalNumbering.toJson(),
    'volumes': volumes.map((Volume v) => v.toJson()).toList(),
  };

  static BookIndex fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = json['volumes'] as List<dynamic>? ?? <dynamic>[];
    return BookIndex(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名作品',
      notes: json['notes'] as String? ?? '',
      // 旧数据没有全局编号：默认关闭，迁移后视觉行为不变。
      globalNumbering: ChapterNumbering.fromJson(
        json['globalNumbering'] as Map<String, dynamic>? ?? const {},
      ),
      volumes: raw
          .whereType<Map<String, dynamic>>()
          .map(Volume.fromJson)
          .toList(),
    );
  }
}

class Volume {
  Volume({
    required this.id,
    required this.title,
    required this.order,
    this.numbering = const ChapterNumbering(),
    this.numberingMode = VolumeNumberingMode.followGlobal,
    List<ChapterMeta>? chapters,
  }) : chapters = chapters ?? <ChapterMeta>[];

  final String id;
  String title;
  int order;
  final List<ChapterMeta> chapters;

  /// 卷级编号规则：仅在 [VolumeNumberingMode.independent] 模式下生效。
  /// 字段沿用旧的每卷独立编号设置（保留用户已配置的规则）。
  ChapterNumbering numbering;

  /// 卷级编号模式（两层编号的卷层），新卷默认跟随全局编号。
  VolumeNumberingMode numberingMode;

  int get wordCount =>
      chapters.fold(0, (int s, ChapterMeta c) => s + c.wordCount);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'order': order,
    'chapters': chapters.map((ChapterMeta c) => c.toJson()).toList(),
    'numbering': numbering.toJson(),
    'numberingMode': numberingMode.code,
  };

  static Volume fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw = json['chapters'] as List<dynamic>? ?? <dynamic>[];
    final ChapterNumbering numbering = ChapterNumbering.fromJson(
      json['numbering'] as Map<String, dynamic>? ?? const {},
    );
    // 旧数据迁移：没有 numberingMode（或值无法识别）时按旧开关推导——
    // 已启用独立编号的卷 → 卷内独立编号（保留其规则）；否则跟随全局编号。
    final VolumeNumberingMode mode =
        VolumeNumberingMode.tryFromCode(json['numberingMode']) ??
        (numbering.enabled
            ? VolumeNumberingMode.independent
            : VolumeNumberingMode.followGlobal);
    return Volume(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名卷',
      order: (json['order'] as num?)?.toInt() ?? 0,
      numbering: numbering,
      numberingMode: mode,
      chapters: raw
          .whereType<Map<String, dynamic>>()
          .map(ChapterMeta.fromJson)
          .toList(),
    );
  }
}

class ChapterMeta {
  ChapterMeta({
    required this.id,
    required this.title,
    required this.order,
    this.wordCount = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  String title;
  int order;
  int wordCount;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'order': order,
    'wordCount': wordCount,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static ChapterMeta fromJson(Map<String, dynamic> json) => ChapterMeta(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '未命名章',
    order: (json['order'] as num?)?.toInt() ?? 0,
    wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
    updatedAt: _parseDate(json['updatedAt']),
  );
}

/// 用户自定义主题（settings.json `customThemes` 数组元素）。
///
/// 纯 Dart 模型，不依赖 Flutter：颜色以 0xAARRGGBB 整数持久化。
class CustomTheme {
  CustomTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.accent,
  });

  final String id;
  final String name;
  final int background;
  final int accent;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'background': background,
    'accent': accent,
  };

  /// 单条解析；字段缺失/类型不符返回 null（损坏条目被跳过，不影响其余）。
  static CustomTheme? tryParse(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final String? id = value['id'] as String?;
    final String? name = value['name'] as String?;
    final int? background = (value['background'] as num?)?.toInt();
    final int? accent = (value['accent'] as num?)?.toInt();
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.isEmpty ||
        background == null ||
        accent == null ||
        background < 0 ||
        background > 0xFFFFFFFF ||
        accent < 0 ||
        accent > 0xFFFFFFFF) {
      return null;
    }
    return CustomTheme(
      id: id,
      name: name,
      background: background,
      accent: accent,
    );
  }
}

/// 应用设置（PLAN.md §4.1 settings.json / §6.6）。
class AppSettings {
  AppSettings({
    this.themeMode = 'system',
    this.language = 'zh-CN',
    this.fontSize = 18,
    this.lineHeight = 1.9,
    this.autoIndent = true,
    this.blankLineBetween = false,
    this.windowX,
    this.windowY,
    this.windowWidth,
    this.windowHeight,
    this.windowMaximized = false,
    this.exportDirectory,
    this.lastOpenedBookId,
    this.sidebarCollapsed = false,
    List<CustomTheme>? customThemes,
    Map<String, List<String>>? expandedVolumes,
  }) : customThemes = customThemes ?? <CustomTheme>[],
       expandedVolumes = expandedVolumes ?? <String, List<String>>{};

  /// system | light | dark | `custom:<CustomTheme.id>`
  String themeMode;

  /// 界面语言（i18n 语言包 code，如 `zh-CN` / `en`）；
  /// 未注册的 code 由 i18n 层在应用时回退默认语言。
  String language;
  double fontSize; // 14–28
  double lineHeight; // 1.4–2.4
  bool autoIndent;
  bool blankLineBetween;
  double? windowX;
  double? windowY;
  double? windowWidth;
  double? windowHeight;
  bool windowMaximized;
  String? exportDirectory;
  String? lastOpenedBookId;
  final Map<String, List<String>> expandedVolumes;
  bool sidebarCollapsed;

  /// 用户自定义主题，最多 [SettingsController.customThemeLimit] 套。
  final List<CustomTheme> customThemes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode,
    'language': language,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'autoIndent': autoIndent,
    'blankLineBetween': blankLineBetween,
    'windowX': windowX,
    'windowY': windowY,
    'windowWidth': windowWidth,
    'windowHeight': windowHeight,
    'windowMaximized': windowMaximized,
    'exportDirectory': exportDirectory,
    'lastOpenedBookId': lastOpenedBookId,
    'expandedVolumes': expandedVolumes,
    'sidebarCollapsed': sidebarCollapsed,
    'customThemes': customThemes.map((CustomTheme t) => t.toJson()).toList(),
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> rawExpanded =
        (json['expandedVolumes'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    // 向后兼容：旧 settings.json 无 customThemes 字段时得到空列表；
    // 字段损坏（非列表/条目非法）时逐条跳过，不阻断其余设置。
    final List<CustomTheme> customThemes =
        (json['customThemes'] as List<dynamic>? ?? <dynamic>[])
            .map(CustomTheme.tryParse)
            .whereType<CustomTheme>()
            .take(4)
            .toList();
    String themeMode = json['themeMode'] as String? ?? 'system';
    if (themeMode.startsWith('custom:') &&
        !customThemes.any((CustomTheme t) => 'custom:${t.id}' == themeMode)) {
      // 引用已不存在的自定义主题：回退跟随系统。
      themeMode = 'system';
    }
    return AppSettings(
      themeMode: themeMode,
      language: _parseLanguage(json['language']),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.9,
      autoIndent: json['autoIndent'] as bool? ?? true,
      blankLineBetween: json['blankLineBetween'] as bool? ?? false,
      windowX: (json['windowX'] as num?)?.toDouble(),
      windowY: (json['windowY'] as num?)?.toDouble(),
      windowWidth: (json['windowWidth'] as num?)?.toDouble(),
      windowHeight: (json['windowHeight'] as num?)?.toDouble(),
      windowMaximized: json['windowMaximized'] as bool? ?? false,
      exportDirectory: json['exportDirectory'] as String?,
      lastOpenedBookId: json['lastOpenedBookId'] as String?,
      sidebarCollapsed: json['sidebarCollapsed'] as bool? ?? false,
      customThemes: customThemes,
      expandedVolumes: rawExpanded.map(
        (String k, dynamic v) => MapEntry<String, List<String>>(
          k,
          (v as List<dynamic>? ?? <dynamic>[]).whereType<String>().toList(),
        ),
      ),
    );
  }
}

DateTime _parseDate(dynamic value) {
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  return DateTime.now();
}

/// 语言字段容错：非字符串或空白回退默认 `zh-CN`。
String _parseLanguage(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return 'zh-CN';
}
