/// 书架上的相对时间（PLAN.md §6.3）：刚刚 / N 分钟前 / 昨天 / 日期。
String relativeTime(DateTime time, {DateTime? now}) {
  final DateTime at = now ?? DateTime.now();
  final Duration diff = at.difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  final DateTime dayOf = DateTime(time.year, time.month, time.day);
  final DateTime dayNow = DateTime(at.year, at.month, at.day);
  final int days = dayNow.difference(dayOf).inDays;
  if (days == 0) return '${diff.inHours} 小时前';
  if (days == 1) return '昨天';
  if (days < 7) return '$days 天前';
  return '${time.year}-${_two(time.month)}-${_two(time.day)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 保存状态的人话（PLAN.md §7.3）。
String saveStateLabel(String stateName, DateTime? lastSavedAt) {
  switch (stateName) {
    case 'saving':
      return '保存中…';
    case 'failed':
      return '保存失败';
    case 'blocked':
      return '等待输入法上屏';
    case 'dirty':
      return '未保存';
    default:
      return lastSavedAt == null ? '已保存' : '已保存 · ${relativeTime(lastSavedAt)}';
  }
}
