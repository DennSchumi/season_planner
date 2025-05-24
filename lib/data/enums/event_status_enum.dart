enum EventStatusEnum{
  scheduled('Scheduled'),provisional('Provisional'),canceled('Canceled'),running('Running'),done('Done');

  final String label;

  const EventStatusEnum(this.label);
}