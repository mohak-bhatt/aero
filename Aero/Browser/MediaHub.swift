import AppKit
import Combine
import WebKit

struct MediaInfo: Equatable {
    var isPlaying: Bool
    var isVideo: Bool
    var title: String
    var artist: String
    var artworkURL: URL?
    var duration: Double
    var currentTime: Double
    var isMainFrame: Bool = true
    var videoWidth: Double = 0
    var videoHeight: Double = 0
    var videoAspectRatio: CGFloat {
        guard videoWidth.isFinite, videoHeight.isFinite, videoWidth > 0, videoHeight > 0,
              (videoWidth / videoHeight).isFinite, videoWidth / videoHeight > 0 else { return 16.0 / 9.0 }
        return CGFloat(videoWidth / videoHeight)
    }
}

/// Which tabs currently have audio/video, newest first. Drives the sidebar mini-player.
@MainActor
final class MediaHub: ObservableObject {
    static let shared = MediaHub()
    @Published private(set) var items: [UUID: MediaInfo] = [:]
    @Published private(set) var order: [UUID] = []

    @Published private(set) var dismissed = Set<UUID>()
    @Published private(set) var explicit = Set<UUID>()
    func dismiss(_ id: UUID) { dismissed.insert(id); explicit.remove(id) }
    func show(_ id: UUID) { dismissed.remove(id); explicit.insert(id) }
    func forget(_ id: UUID) { update(id, nil); dismissed.remove(id); explicit.remove(id) }
    func permits(_ id: UUID, url: URL?) -> Bool {
        guard !dismissed.contains(id) else { return false }
        let host = url?.host?.lowercased() ?? ""
        return explicit.contains(id) || !(host == "instagram.com" || host.hasSuffix(".instagram.com"))
    }

    func update(_ id: UUID, _ info: MediaInfo?) {
        if let info {
            if items[id] != info { items[id] = info }
            if !order.contains(id) { order.removeAll { $0 == id }; order.insert(id, at: 0) }
        } else if items[id] != nil {
            items.removeValue(forKey: id)
            order.removeAll { $0 == id }
        }
    }
}

final class MediaMessageHandler: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?
    init(tab: BrowserTab) { self.tab = tab }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let frame = message.frameInfo
        Task { @MainActor in self.tab?.handleMedia(body, frame: frame) }
    }
}

enum MediaScript {
    static let source = """
    (function () {
      if (window.__aero) return;
      var current = null, last = 0, saved = [], handlers = {}, lifted = null, hadControls = false, positionState = null;
      var musicHosts = /(music[.]youtube|spotify|music[.]apple|soundcloud|deezer|tidal|pandora|bandcamp|jiosaavn|gaana|wynk|audiomack)/i;
      try {
        if (window.MediaSession && MediaSession.prototype.setActionHandler) {
          var original = MediaSession.prototype.setActionHandler;
          MediaSession.prototype.setActionHandler = function (action, handler) { handlers[action] = handler; return original.apply(this, arguments); };
        }
      } catch (e) {}
      try {
        if (window.MediaSession && MediaSession.prototype.setPositionState) {
          var originalPosition = MediaSession.prototype.setPositionState;
          MediaSession.prototype.setPositionState = function (state) {
            var result = originalPosition.apply(this, arguments);
            positionState = state && isFinite(state.duration) && state.duration > 0
              ? { duration: state.duration, position: state.position || 0,
                  rate: state.playbackRate === undefined ? 1 : state.playbackRate, at: performance.now() } : null;
            return result;
          };
        }
      } catch (e) {}
      function sessionPosition() {
        if (!positionState) return { duration: 0, time: 0 };
        var elapsed = navigator.mediaSession.playbackState === 'playing'
          ? (performance.now() - positionState.at) / 1000 * positionState.rate : 0;
        return { duration: positionState.duration,
                 time: Math.max(0, Math.min(positionState.duration, positionState.position + elapsed)) };
      }
      function isVisibleVideo(el) {
        if (el.tagName !== 'VIDEO' || !(el.videoWidth > 0) || musicHosts.test(location.hostname)) return false;
        var r = el.getBoundingClientRect(), cs = getComputedStyle(el);
        return r.width >= 120 && r.height >= 68 && cs.display !== 'none' && cs.visibility !== 'hidden';
      }
      function meta() {
        var m = navigator.mediaSession && navigator.mediaSession.metadata, art = null;
        if (m && m.artwork && m.artwork.length) art = m.artwork[m.artwork.length - 1].src;
        return { title: (m && m.title) || document.title, artist: (m && (m.artist || m.album)) || location.hostname, artwork: art };
      }
      function send(payload) { try { window.webkit.messageHandlers.aeroMedia.postMessage(payload); } catch (e) {} }
      function reportSession() {
        var s = navigator.mediaSession;
        if (!s || !s.metadata || (s.playbackState !== 'playing' && s.playbackState !== 'paused')) return;
        var m = meta(), position = sessionPosition();
        send({ playing: s.playbackState === 'playing', video: false, title: m.title,
               artist: m.artist, artwork: m.artwork, duration: position.duration, time: position.time });
      }
      // Preserve the native setter; publish only the state actually accepted by the player.
      try {
        var playback = Object.getOwnPropertyDescriptor(MediaSession.prototype, 'playbackState');
        if (playback && playback.set && playback.get && playback.configurable) {
          Object.defineProperty(MediaSession.prototype, 'playbackState', {
            configurable: playback.configurable, enumerable: playback.enumerable,
            get: playback.get,
            set: function (value) {
              var position = sessionPosition();
              playback.set.call(this, value);
              if (positionState) { positionState.position = position.time; positionState.at = performance.now(); }
              commandPendingUntil = 0;
              reportSession();
            }
          });
        }
      } catch (e) {}
      function sessionOwnsPlayback() {
        var s = navigator.mediaSession;
        return s && s.metadata && (handlers.play || handlers.pause) &&
          (s.playbackState === 'playing' || s.playbackState === 'paused') &&
          (!current || !isVisibleVideo(current));
      }
      function post(force) {
        if (sessionOwnsPlayback()) { reportSession(); return; }
        var el = current; if (!el) return;
        var now = Date.now(); if (!force && now - last < 900) return; last = now;
        var m = meta();
        send({ playing: !el.paused && !el.ended, video: isVisibleVideo(el),
               title: m.title, artist: m.artist, artwork: m.artwork || el.poster || null,
               duration: isFinite(el.duration) ? el.duration : 0, time: el.currentTime, width: el.videoWidth || 0, height: el.videoHeight || 0 });
      }
      var tabMuted = false, originalMute = new WeakMap();
      function applyMute(el) {
        if (tabMuted) { if (!originalMute.has(el)) originalMute.set(el, el.muted); el.muted = true; }
        else if (originalMute.has(el)) { el.muted = originalMute.get(el); originalMute.delete(el); }
      }
      function setMuted(value) {
        tabMuted = !!value;
        document.querySelectorAll('video,audio').forEach(applyMute);
        for (var i = 0; i < window.frames.length; i++) window.frames[i].postMessage({aeroTabMuted: tabMuted}, '*');
      }
      window.addEventListener('message', function (event) {
        if (window.parent !== window && event.source === window.parent && event.data && typeof event.data.aeroTabMuted === 'boolean') setMuted(event.data.aeroTabMuted);
      });
      function attach(el) {
        applyMute(el);
        if (el.__aeroBound) return; el.__aeroBound = true;
        ['play', 'playing', 'pause', 'ended', 'timeupdate', 'durationchange', 'seeked', 'loadedmetadata', 'resize'].forEach(function (ev) {
          el.addEventListener(ev, function () {
            if (ev === 'play' || ev === 'playing') current = el;
            if (!current && !el.paused) current = el;
            if (el === current) post(ev !== 'timeupdate');
          }, true);
        });
        if (!el.paused && !current) { current = el; post(true); }
      }
      function scan() { document.querySelectorAll('video,audio').forEach(attach); }
      new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
      scan();
      // Players that use Web Audio instead of <audio>: fall back to Media Session metadata.
      setInterval(function () { if (!current || sessionOwnsPlayback()) reportSession(); }, 500);
      var commandPendingUntil = 0;


      function keep(node) { for (var i = 0; i < saved.length; i++) if (saved[i][0] === node) return; saved.push([node, node.getAttribute('style')]); }
      function important(node, props) { keep(node); for (var k in props) node.style.setProperty(k, props[k], 'important'); }
      function lift(el) {
        unlift();
        lifted = el; hadControls = el.controls; el.controls = false;
        var node = el;
        while (node && node !== document.documentElement) {
          var parent = node.parentElement;
          if (parent) Array.prototype.forEach.call(parent.children, function (sibling) {
            if (sibling !== node) important(sibling, { visibility: 'hidden' });
          });
          if (node !== el) important(node, { transform: 'none', filter: 'none', contain: 'none', overflow: 'visible', opacity: '1' });
          node = parent;
        }
        important(document.documentElement, { overflow: 'hidden' });
        important(el, { position: 'fixed', top: '0', left: '0', width: '100vw', height: '100vh', 'max-width': 'none',
                        'max-height': 'none', margin: '0', 'z-index': '2147483647', background: '#000',
                        'object-fit': 'contain', visibility: 'visible', transform: 'none' });
      }
      function unlift() {
        if (lifted) { lifted.controls = hadControls; lifted = null; }
        saved.forEach(function (p) { if (p[1] === null) p[0].removeAttribute('style'); else p[0].setAttribute('style', p[1]); });
        saved = [];
      }
      window.__aero = {
        setMuted: setMuted,
        prev: function () { if (handlers.previoustrack) handlers.previoustrack({ action: 'previoustrack' }); else if (current) current.currentTime = 0; },
        next: function () { if (handlers.nexttrack) handlers.nexttrack({ action: 'nexttrack' }); else if (current) current.currentTime = current.currentTime + 10; },
        mute: function () { if (current) { current.muted = !current.muted; post(true); } },
        seek: function (time) { if (!isFinite(time)) return; if (handlers.seekto) { handlers.seekto({ action: 'seekto', seekTime: Math.max(0, positionState ? Math.min(positionState.duration, time) : time), fastSeek: false }); return; } if (current && isFinite(time) && isFinite(current.duration)) { current.currentTime = Math.max(0, Math.min(current.duration, time)); post(true); } },
        play: function () { window.__aero.toggle('play'); },
        pause: function () { window.__aero.toggle('pause'); },
        toggle: function (requestedAction) {
          var session = navigator.mediaSession;
          if (Date.now() < commandPendingUntil) return;
          var sessionKnown = session && (session.playbackState === 'playing' || session.playbackState === 'paused');
          var playing = sessionKnown && (handlers.play || handlers.pause)
            ? session.playbackState === 'playing' : current && !current.paused;
          var action = requestedAction || (playing ? 'pause' : 'play');
          if (handlers[action]) {
            commandPendingUntil = Date.now() + 750;
            try { handlers[action]({ action: action }); }
            catch (e) { commandPendingUntil = 0; }
            reportSession();
            return;
          }
          if (current) {
            if (action === 'pause') current.pause();
            else { var promise = current.play(); if (promise && promise.catch) promise.catch(function () { post(true); }); }
          }
        },
        back10: function () { if (current) current.currentTime = Math.max(0, current.currentTime - 10); },
        fwd10: function () { if (current) current.currentTime = current.currentTime + 10; },
        pip: function () { if (current && current.webkitSetPresentationMode) current.webkitSetPresentationMode('picture-in-picture'); },
        lift: function () { if (current && current.tagName === 'VIDEO') lift(current); },
        unlift: unlift
      };
    })();
    """
}
