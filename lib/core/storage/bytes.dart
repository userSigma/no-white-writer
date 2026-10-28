/// 字节逐位相等比较。core/storage 保持纯 Dart（不引入
/// flutter/foundation 的 listEquals），供迁移校验与导出复查共用。
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
