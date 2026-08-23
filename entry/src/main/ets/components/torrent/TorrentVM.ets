// transmissionbtm — TorrentVM (ArkUI-observable wrapper for a TorrentInfo)
//
// The torrent models (TorrentInfo) stay plain, host-testable data classes — they
// must NOT carry ArkUI decorators (host vitest runs them in Node, which cannot
// parse @Observed). But ArkUI's ForEach reuses a list child by stable key and
// does NOT re-apply a new @Prop value on reuse, so a polled torrent card would
// keep first-render data ("only refreshes after restart"). Wrapping each
// TorrentInfo in an @Observed view-model and binding the card with @ObjectLink
// lets the reused card observe an in-place `torrent` reassignment each poll and
// re-render live, WITHOUT recreating the component (so expansion state, etc.,
// survives).
//
// Callers:
//   DownloadsPage — builds the @State TorrentVM[] and mutates each VM's
//                   `torrent` field in place on every poll.
//   TorrentCard   — binds `@ObjectLink vm` and reads `vm.torrent.*`.

import { TorrentInfo } from '../../models/TorrentInfo';

@Observed
export class TorrentVM {
  torrent: TorrentInfo;

  constructor(torrent: TorrentInfo) {
    this.torrent = torrent;
  }
}
