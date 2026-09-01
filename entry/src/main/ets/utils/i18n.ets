// transmissionbtm — UI locale helpers.
//
// Model-layer code (and its host/on-device tests) asserts `getStatusString()`
// returns plain-English literals ('Paused', 'Downloading', …), so the model is
// kept pure and localization happens ONLY here at the display boundary. This
// maps a status string to an `$r` Resource; anything we don't recognize (e.g. a
// custom errorString passed through from libtransmission) is returned as-is.

export function statusResource(s: string): ResourceStr {
  if (s === 'Completed') return $r('app.string.torrent_status_completed');
  if (s === 'Paused') return $r('app.string.torrent_status_paused');
  if (s === 'Verifying') return $r('app.string.torrent_status_verifying');
  if (s === 'Downloading') return $r('app.string.torrent_status_downloading');
  if (s === 'Seeding') return $r('app.string.torrent_status_seeding');
  if (s === 'Error') return $r('app.string.torrent_status_error');
  return s; // passthrough (e.g. an errorString surfaced by the engine)
}
