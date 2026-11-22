bool hasSevenDaysOfFeedValidityLeft(
  DateTime feedEndDate, {
  required DateTime today,
}) {
  final firstValidToday = DateTime(today.year, today.month, today.day);
  final lastValidDay = DateTime(
    feedEndDate.year,
    feedEndDate.month,
    feedEndDate.day,
  );
  return !lastValidDay.isBefore(firstValidToday.add(const Duration(days: 7)));
}
