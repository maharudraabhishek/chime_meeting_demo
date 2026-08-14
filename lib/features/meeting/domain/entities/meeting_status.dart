/// Meeting lifecycle states used by the active session state machine.
enum MeetingStatus {
  idle,
  joining,
  connected,
  reconnecting,
  disconnected,
  failed,
}
