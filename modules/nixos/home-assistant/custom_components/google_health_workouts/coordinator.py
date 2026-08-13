"""Coordinator for Google Health Workouts."""

from dataclasses import dataclass, field
from datetime import timedelta
import logging
from typing import TYPE_CHECKING, override

from google_health_api import GoogleHealthApi
from google_health_api.exceptions import (
    GoogleHealthApiError,
    HealthApiForbiddenException,
    HealthAuthException,
)
from google_health_api.model import Exercise

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ConfigEntryAuthFailed
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed
from homeassistant.util import dt as dt_util

from .const import DOMAIN, LOOKBACK_DAYS, POLLING_INTERVAL

if TYPE_CHECKING:
    from . import GoogleHealthWorkoutsConfigEntry

_LOGGER = logging.getLogger(__name__)


@dataclass
class WorkoutData:
    """Holds the latest workout and the recent sessions."""

    latest: Exercise | None = None
    recent_count: int = 0
    recent: list[Exercise] = field(default_factory=list)


class GoogleHealthWorkoutsCoordinator(DataUpdateCoordinator[WorkoutData]):
    """Fetch exercise sessions from the Google Health API."""

    def __init__(
        self,
        hass: HomeAssistant,
        entry: GoogleHealthWorkoutsConfigEntry,
        api_client: GoogleHealthApi,
    ) -> None:
        """Initialize the coordinator."""
        self.api = api_client
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=POLLING_INTERVAL,
            config_entry=entry,
        )

    @override
    async def _async_update_data(self) -> WorkoutData:
        """Fetch recent exercise sessions (newest first)."""
        try:
            result = await self.api.exercise.list(
                start_time=dt_util.now() - timedelta(days=LOOKBACK_DAYS),
                page_size=25,
            )
        except (HealthAuthException, HealthApiForbiddenException) as err:
            raise ConfigEntryAuthFailed(
                translation_domain=DOMAIN,
                translation_key="auth_error",
            ) from err
        except GoogleHealthApiError as err:
            raise UpdateFailed(
                translation_domain=DOMAIN,
                translation_key="communication_error",
            ) from err

        points = result.data_points
        latest = points[0].data if points else None
        return WorkoutData(
            latest=latest,
            recent_count=len(points),
            recent=[p.data for p in points],
        )
