const rawBaseUrl = process.env.MEETING_API_BASE_URL;
if (typeof rawBaseUrl !== "string" || rawBaseUrl.length === 0) {
  throw new Error("MEETING_API_BASE_URL is required.");
}
const meetingsUrl = new URL("meetings", rawBaseUrl).toString();

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function validPlacement(value) {
  if (typeof value !== "object" || value === null) return false;
  return [
    "AudioHostUrl",
    "AudioFallbackUrl",
    "SignalingUrl",
    "TurnControlUrl",
  ].every((field) => nonEmptyString(value[field]));
}

function safeFailure(prefix, response) {
  console.log(`${prefix}_http_status=${response.status}`);
  console.log(
    `${prefix}_result_category=${response.headers.get("x-gateway-result-category") ?? "absent"}`,
  );
  console.log(
    `${prefix}_upstream_status=${response.headers.get("x-upstream-status") ?? "absent"}`,
  );
}

async function post(body) {
  return fetch(meetingsUrl, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

const createResponse = await post({ type: "agent" });
if (!createResponse.ok) {
  safeFailure("create", createResponse);
  process.exitCode = 1;
} else {
  const create = await createResponse.json();
  const createMeeting = create?.data?.meeting;
  const createAttendee = create?.data?.attendee;
  const meetingId = createMeeting?.MeetingId;
  console.log("create_http_success=true");
  console.log(`create_status_success=${create?.status === "success"}`);
  console.log(`create_meeting_id_exists=${nonEmptyString(meetingId)}`);
  console.log(
    `create_media_placement_valid=${validPlacement(createMeeting?.MediaPlacement)}`,
  );
  console.log(
    `create_attendee_credentials_exist=${nonEmptyString(createAttendee?.AttendeeId) && nonEmptyString(createAttendee?.JoinToken)}`,
  );

  if (!nonEmptyString(meetingId)) {
    process.exitCode = 1;
  } else {
    const joinResponse = await post({ type: "client", meeting_id: meetingId });
    if (!joinResponse.ok) {
      safeFailure("join", joinResponse);
      process.exitCode = 1;
    } else {
      const join = await joinResponse.json();
      const joinMeeting = join?.data?.meeting;
      const joinAttendee = join?.data?.attendee;
      console.log("join_http_success=true");
      console.log(`join_status_success=${join?.status === "success"}`);
      console.log(`join_meeting_id_matches=${joinMeeting?.MeetingId === meetingId}`);
      console.log(
        `join_media_placement_valid=${validPlacement(joinMeeting?.MediaPlacement)}`,
      );
      console.log(
        `join_attendee_credentials_exist=${nonEmptyString(joinAttendee?.AttendeeId) && nonEmptyString(joinAttendee?.JoinToken)}`,
      );
      console.log(
        `join_attendee_is_fresh=${nonEmptyString(joinAttendee?.AttendeeId) && joinAttendee.AttendeeId !== createAttendee?.AttendeeId}`,
      );
    }
  }
}
