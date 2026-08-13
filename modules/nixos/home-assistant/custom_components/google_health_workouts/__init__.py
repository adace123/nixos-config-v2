"""The Google Health Workouts integration."""

from dataclasses import dataclass

from google_health_api import GoogleHealthApi
from google_health_api.const import HealthApiScope

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ConfigEntryAuthFailed, ConfigEntryNotReady
from homeassistant.helpers import aiohttp_client
from homeassistant.helpers.config_entry_oauth2_flow import (
    ImplementationUnavailableError,
    OAuth2Session,
    async_get_config_entry_implementation,
)

from . import api
from .const import DOMAIN
from .coordinator import GoogleHealthWorkoutsCoordinator

_PLATFORMS: list[Platform] = [Platform.SENSOR]


@dataclass
class GoogleHealthWorkoutsData:
    """Runtime data for a Google Health Workouts config entry."""

    coordinator: GoogleHealthWorkoutsCoordinator


type GoogleHealthWorkoutsConfigEntry = ConfigEntry[GoogleHealthWorkoutsData]


async def async_setup_entry(
    hass: HomeAssistant, entry: GoogleHealthWorkoutsConfigEntry
) -> bool:
    """Set up Google Health Workouts from a config entry."""
    try:
        implementation = await async_get_config_entry_implementation(hass, entry)
    except ImplementationUnavailableError as err:
        raise ConfigEntryNotReady(
            translation_domain=DOMAIN,
            translation_key="oauth_error",
        ) from err

    session = OAuth2Session(hass, entry, implementation)

    scopes = session.token.get("scope", "").split()
    if HealthApiScope.ACTIVITY_READ not in scopes:
        raise ConfigEntryAuthFailed(
            translation_domain=DOMAIN,
            translation_key="missing_activity_scope",
        )

    auth = api.AsyncConfigEntryAuth(
        aiohttp_client.async_get_clientsession(hass), session
    )

    api_client = GoogleHealthApi(auth)

    coordinator = GoogleHealthWorkoutsCoordinator(hass, entry, api_client)
    await coordinator.async_config_entry_first_refresh()

    entry.runtime_data = GoogleHealthWorkoutsData(coordinator=coordinator)

    await hass.config_entries.async_forward_entry_setups(entry, _PLATFORMS)

    return True


async def async_unload_entry(
    hass: HomeAssistant, entry: GoogleHealthWorkoutsConfigEntry
) -> bool:
    """Unload a config entry."""
    return await hass.config_entries.async_unload_platforms(entry, _PLATFORMS)
