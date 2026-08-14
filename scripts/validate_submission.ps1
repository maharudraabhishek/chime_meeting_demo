<#
.SYNOPSIS
Runs final Stage 1 quality gates and prepares the Android assessment APK.

.DESCRIPTION
Accepts the public Cloudflare Worker URL, resolves dependencies, verifies
formatting, runs static analysis and tests, builds the Android APK, checks basic
Git hygiene when a repository exists, and copies the APK into the gitignored
artifacts folder for submission. No upstream credential is used by Flutter.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$MeetingApiBaseUrl
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($MeetingApiBaseUrl)) {
    throw 'MeetingApiBaseUrl must not be blank.'
}

$parsedMeetingApiBaseUrl = $null
if (-not [Uri]::TryCreate($MeetingApiBaseUrl.Trim(), [UriKind]::Absolute, [ref]$parsedMeetingApiBaseUrl) -or
    $parsedMeetingApiBaseUrl.Scheme -ne [Uri]::UriSchemeHttps -or
    [string]::IsNullOrWhiteSpace($parsedMeetingApiBaseUrl.Host)) {
    throw 'MeetingApiBaseUrl must be an absolute HTTPS URL.'
}

Write-Host '1/6 Resolving Flutter dependencies...'
flutter pub get

Write-Host '2/6 Verifying Dart formatting...'
dart format --output=none --set-exit-if-changed lib test

Write-Host '3/6 Running static analysis...'
flutter analyze

Write-Host '4/6 Running automated tests...'
flutter test

Write-Host '5/6 Checking repository hygiene...'
if (Test-Path '.git') {
    git diff --check
    $trackedReferences = @(git ls-files -- 'docs/reference')
    if ($trackedReferences.Count -gt 0) {
        throw 'docs/reference contains employer-provided material and must not be tracked.'
    }
}

Write-Host '6/6 Building the Android assessment APK...'
flutter build apk --debug --dart-define=MEETING_API_BASE_URL=$($parsedMeetingApiBaseUrl.AbsoluteUri)

$artifactDirectory = Join-Path $PSScriptRoot '..\artifacts'
$artifactDirectory = [System.IO.Path]::GetFullPath($artifactDirectory)
New-Item -ItemType Directory -Force -Path $artifactDirectory | Out-Null

$sourceApk = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-debug.apk'
$sourceApk = [System.IO.Path]::GetFullPath($sourceApk)
$targetApk = Join-Path $artifactDirectory 'chime-meeting-stage1.apk'
Copy-Item -Force $sourceApk $targetApk

Write-Host "Validation passed. APK prepared at: $targetApk"
Write-Host 'Next: complete the two-device ARM Android acceptance run and record the demo.'
