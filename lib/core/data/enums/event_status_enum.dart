enum EventStatusEnum{
  scheduled('Scheduled'),provisional('Provisional'),canceled('Canceled'),done('Done');

  final String label;

  const EventStatusEnum(this.label);
}