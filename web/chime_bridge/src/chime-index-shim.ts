// Chime 3.32.0's promotion task imports its package barrel for these two
// status symbols. Resolving only that circular edge keeps unrelated Node-only
// messaging exports out of the browser bundle.
export { default as MeetingSessionStatus } from 'amazon-chime-sdk-js/build/meetingsession/MeetingSessionStatus';
export { default as MeetingSessionStatusCode } from 'amazon-chime-sdk-js/build/meetingsession/MeetingSessionStatusCode';

