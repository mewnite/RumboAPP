class PlanSearchCancellation {
  bool isCancelled = false;
  void Function()? _cancelWork;

  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    _cancelWork?.call();
  }

  void attach(void Function() cancelWork) {
    if (isCancelled) {
      cancelWork();
    } else {
      _cancelWork = cancelWork;
    }
  }

  void detach() => _cancelWork = null;
}
