enum EventRoleEnum {
  leader('Leader'), co_leader('Co-Leader'),additional_support('Additional Support'),trainee('Trainee'),camera_crew('Camera Crew');
  final String label;
  const EventRoleEnum(this.label);
}