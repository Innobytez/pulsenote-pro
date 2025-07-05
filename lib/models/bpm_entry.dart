class BpmEntry {
  int bpm;
  String? label;

  BpmEntry({required this.bpm, this.label});

  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'label': label,
  };

  factory BpmEntry.fromJson(Map<String, dynamic> json) => BpmEntry(
    bpm: json['bpm'],
    label: json['label'],
  );

  String get displayLabel => label?.isNotEmpty == true ? label! : '$bpm BPM';
}