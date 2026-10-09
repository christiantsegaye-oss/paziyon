// Keeps the last known position so an alert always has something to send,
// even when a fresh GPS fix is slow or unavailable (spec 5.2 LocationService).

let last = null;
let watchId = null;

export function startLocation(onUpdate = () => {}) {
  if (!navigator.geolocation || watchId !== null) return;
  watchId = navigator.geolocation.watchPosition(
    (pos) => {
      last = { lat: +pos.coords.latitude.toFixed(5), lng: +pos.coords.longitude.toFixed(5), at: pos.timestamp };
      onUpdate(last);
    },
    () => onUpdate(null),
    { enableHighAccuracy: true, maximumAge: 30_000, timeout: 20_000 },
  );
}

export const lastLocation = () => last;
