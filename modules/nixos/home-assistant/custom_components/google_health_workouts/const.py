"""Constants for the Google Health Workouts integration."""

from datetime import timedelta

from google_health_api.const import HealthApiScope

DOMAIN = "google_health_workouts"

OAUTH2_AUTHORIZE = "https://accounts.google.com/o/oauth2/v2/auth"
OAUTH2_TOKEN = "https://oauth2.googleapis.com/token"

DEFAULT_TITLE = "Google Health Workouts"

# Reading exercise sessions requires the activity scope; profile scopes are
# needed to verify account identity and complete the OAuth flow.
OAUTH_SCOPES = [
    HealthApiScope.ACTIVITY_READ,
    HealthApiScope.PROFILE_READ,
    HealthApiScope.USERINFO_PROFILE,
]

POLLING_INTERVAL = timedelta(minutes=10)
LOOKBACK_DAYS = 30
