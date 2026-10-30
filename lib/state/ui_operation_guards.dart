/// 跨页面草稿守卫：设置打开和原生退出共用同一组注册项。
class UiOperationGuards {
  final Map<Object, Future<bool> Function()> _guards = {};
  Object register(Future<bool> Function() guard) {
    final token = Object();
    _guards[token] = guard;
    return token;
  }

  void remove(Object token) => _guards.remove(token);

  Future<bool> flush() async {
    try {
      for (final entry in _guards.entries.toList()) {
        if (_guards.containsKey(entry.key) && !await entry.value()) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
