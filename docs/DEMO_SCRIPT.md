# Android demo script

Target duration: **under 5 minutes**. Record the running application on two Android devices; do not use the video to show only source code or the repository.

1. **Create meeting — Device A**
   - Launch Chime Meeting.
   - Tap **Create meeting**.
   - Grant camera and microphone permissions if prompted.
   - Show `Joining`, then `Connected`.
   - Copy/show the generated meeting ID.

2. **Join same meeting — Device B**
   - Launch the app.
   - Paste the exact meeting ID from Device A.
   - Tap **Join meeting**.
   - Show `Joining`, then `Connected`.

3. **Two-way media**
   - Show local preview on both devices.
   - Show remote video on both devices.
   - Briefly confirm audio is connected.

4. **Required controls**
   - Toggle microphone off/on and show the UI state change.
   - Toggle camera off/on and show the local/remote video behavior.

5. **Event log**
   - Open **Meeting event log**.
   - Show real entries for meeting start, participant join, microphone change, and camera change.

6. **Leave**
   - Leave from one device.
   - Show `Disconnected` and the meeting-ended/participant-left event where available.

Do not expose the API key, JoinToken, attendee credentials, terminal output containing secrets, or employer-provided Postman credentials in the recording.
