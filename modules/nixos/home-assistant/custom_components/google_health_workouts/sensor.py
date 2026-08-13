"""Sensors for Google Health Workouts."""

from dataclasses import dataclass
from typing import Any, Callable, override

from google_health_api.model import Exercise

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorEntityDescription,
    SensorStateClass,
)
from homeassistant.const import (
    UnitOfLength,
    UnitOfSpeed,
    UnitOfTime,
)
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback
from homeassistant.helpers.typing import StateType
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import GoogleHealthWorkoutsCoordinator, WorkoutData

PARALLEL_UPDATES = 0

MM_PER_MILE = 1_609_344
MM_PER_FOOT = 304.8
MMS_PER_MPH = 0.0022369362920544


def _duration_minutes(ex: Exercise | None) -> float | None:
    """Parse an activeDuration string like '1852s' into minutes."""
    if ex is None or not ex.active_duration:
        return None
    try:
        return float(ex.active_duration.rstrip("s")) / 60
    except ValueError:
        return None


@dataclass(frozen=True, kw_only=True)
class WorkoutSensorEntityDescription(SensorEntityDescription):
    """Class describing Google Health Workouts sensor entities."""

    value_fn: Callable[[WorkoutData], StateType]


SENSOR_DESCRIPTIONS: list[WorkoutSensorEntityDescription] = [
    WorkoutSensorEntityDescription(
        key="type",
        name="Last Workout Type",
        icon="mdi:run-fast",
        value_fn=lambda data: (
            data.latest.exercise_type.replace("_", " ").title()
            if data and data.latest
            else None
        ),
    ),
    WorkoutSensorEntityDescription(
        key="duration",
        name="Last Workout Duration",
        icon="mdi:timer-outline",
        native_unit_of_measurement=UnitOfTime.MINUTES,
        device_class=SensorDeviceClass.DURATION,
        value_fn=lambda data: _duration_minutes(data.latest if data else None),
    ),
    WorkoutSensorEntityDescription(
        key="distance",
        name="Last Workout Distance",
        icon="mdi:map-marker-distance",
        native_unit_of_measurement=UnitOfLength.MILES,
        device_class=SensorDeviceClass.DISTANCE,
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda data: (
            round(
                data.latest.metrics_summary.distance_millimeters / MM_PER_MILE, 2
            )
            if data and data.latest and data.latest.metrics_summary.distance_millimeters
            else None
        ),
    ),
    WorkoutSensorEntityDescription(
        key="avg_speed",
        name="Last Workout Average Speed",
        icon="mdi:speedometer",
        native_unit_of_measurement=UnitOfSpeed.MILES_PER_HOUR,
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda data: (
            round(
                data.latest.metrics_summary.average_speed_millimeters_per_second
                * MMS_PER_MPH,
                2,
            )
            if data
            and data.latest
            and data.latest.metrics_summary.average_speed_millimeters_per_second
            else None
        ),
    ),
    WorkoutSensorEntityDescription(
        key="avg_heart_rate",
        name="Last Workout Average Heart Rate",
        icon="mdi:heart-pulse",
        native_unit_of_measurement="bpm",
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda data: (
            data.latest.metrics_summary.average_heart_rate_beats_per_minute
            if data
            and data.latest
            and data.latest.metrics_summary.average_heart_rate_beats_per_minute
            else None
        ),
    ),
    WorkoutSensorEntityDescription(
        key="calories",
        name="Last Workout Calories",
        icon="mdi:fire",
        native_unit_of_measurement="kcal",
        device_class=SensorDeviceClass.ENERGY,
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda data: (
            round(data.latest.metrics_summary.calories_kcal, 0)
            if data and data.latest and data.latest.metrics_summary.calories_kcal
            else None
        ),
    ),
    WorkoutSensorEntityDescription(
        key="elevation",
        name="Last Workout Elevation",
        icon="mdi:image-filter-hdr",
        native_unit_of_measurement=UnitOfLength.FEET,
        device_class=SensorDeviceClass.DISTANCE,
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda data: (
            round(
                data.latest.metrics_summary.elevation_gain_millimeters / MM_PER_FOOT,
                0,
            )
            if data
            and data.latest
            and data.latest.metrics_summary.elevation_gain_millimeters is not None
            else None
        ),
    ),
    WorkoutSensorEntityDescription(
        key="recent_count",
        name="Workouts Last 30 Days",
        icon="mdi:bike",
        state_class=SensorStateClass.TOTAL_INCREASING,
        value_fn=lambda data: data.recent_count if data else None,
    ),
]


class WorkoutSensorEntity(
    CoordinatorEntity[GoogleHealthWorkoutsCoordinator], SensorEntity
):
    """Sensor for the latest Google Health workout."""

    entity_description: WorkoutSensorEntityDescription

    def __init__(
        self,
        coordinator: GoogleHealthWorkoutsCoordinator,
        description: WorkoutSensorEntityDescription,
    ) -> None:
        """Initialize the sensor."""
        super().__init__(coordinator)
        self.entity_description = description
        self._attr_unique_id = f"{DOMAIN}_{description.key}"
        self._attr_name = description.name

    @property
    def native_value(self) -> StateType:
        """Return the sensor value."""
        return self.entity_description.value_fn(self.coordinator.data)

    @property
    @override
    def extra_state_attributes(self) -> dict[str, Any] | None:
        """Return workout session details on the type sensor."""
        if self.entity_description.key != "type":
            return None
        data = self.coordinator.data
        ex = data.latest if data else None
        if ex is None:
            return None
        return {
            "display_name": ex.display_name,
            "start_time": ex.interval.start_time,
            "end_time": ex.interval.end_time,
            "active_duration": ex.active_duration,
            "has_gps": ex.exercise_metadata.has_gps if ex.exercise_metadata else None,
        }


async def async_setup_entry(
    hass: HomeAssistant,
    entry: GoogleHealthWorkoutsConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    """Set up Google Health Workouts sensors from a config entry."""
    coordinator = entry.runtime_data.coordinator
    async_add_entities(
        WorkoutSensorEntity(coordinator, description)
        for description in SENSOR_DESCRIPTIONS
    )
