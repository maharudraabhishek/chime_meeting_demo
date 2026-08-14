// Google Apps Script fallback relay for Hipster's cloud-egress challenge.
// Store only RELAY_SHARED_SECRET in Script Properties. The Hipster key is
// supplied transiently by the Cloudflare Worker and is never stored here.
const HIPSTER_URL = 'https://assess.hipster-dev.com/api/meetings';

function doPost(event) {
  try {
    const input = JSON.parse(event.postData.contents);
    const expectedRelaySecret = PropertiesService.getScriptProperties()
      .getProperty('RELAY_SHARED_SECRET');
    if (!expectedRelaySecret || input.relay_token !== expectedRelaySecret) {
      return jsonResponse({ status: 'error', error: { code: 'UNAUTHORIZED' } });
    }

    const apiKey = input.relay_api_key;
    if (typeof apiKey !== 'string' || apiKey.length === 0) {
      return jsonResponse({ status: 'error', error: { code: 'INVALID_UPSTREAM_CREDENTIAL' } });
    }

    delete input.relay_token;
    delete input.relay_api_key;

    const upstream = UrlFetchApp.fetch(HIPSTER_URL, {
      method: 'post',
      contentType: 'application/json',
      headers: {
        Accept: 'application/json',
        'User-Agent': 'chime-meeting-apps-script/1.0',
        'x-api-key': apiKey,
      },
      payload: JSON.stringify(input),
      muteHttpExceptions: true,
    });

    return ContentService
      .createTextOutput(upstream.getContentText())
      .setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return jsonResponse({ status: 'error', error: { code: 'UPSTREAM_UNAVAILABLE' } });
  }
}

function jsonResponse(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
