//
//  MediaInfo.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


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
}

/// Which tabs currently have audio/video, newest first. Drives the sidebar mini-player.
@MainActor
final class MediaHub: ObservableObject {
    static let shared = MediaHub()
    @Published private(set) var items: [UUID: MediaInfo] = [:]
    @Published private(set) var order: [UUID] = []

    func update(_ id: UUID, _ info: MediaInfo?) {
        if let info {
            if items[id] != info { items[id] = info }
            if order.first != id { order.removeAll { $0 == id }; order.insert(id, at: 0) }
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
        Task { @MainActor in self.tab?.handleMedia(body) }
    }
}

enum MediaScript {
    static let source = """
    (function () {
      if (window.__aero) return;
      var current = null, last = 0;
      function meta() {
        var m = navigator.mediaSession && navigator.mediaSession.metadata, art = null;
        if (m && m.artwork && m.artwork.length) art = m.artwork[m.artwork.length - 1].src;
        return { title: (m && m.title) || document.title, artist: (m && (m.artist || m.album)) || location.hostname, artwork: art };
      }
      function post(force) {
        var el = current; if (!el) return;
        var now = Date.now(); if (!force && now - last < 900) return; last = now;
        var m = meta();
        window.webkit.messageHandlers.aeroMedia.postMessage({
          playing: !el.paused && !el.ended, video: el.tagName === 'VIDEO',
          title: m.title, artist: m.artist, artwork: m.artwork || el.poster || null,
          duration: isFinite(el.duration) ? el.duration : 0, time: el.currentTime });
      }
      function attach(el) {
        if (el.__aeroBound) return; el.__aeroBound = true;
        ['play', 'playing', 'pause', 'ended', 'timeupdate', 'durationchange', 'seeked'].forEach(function (ev) {
          el.addEventListener(ev, function () {
            if (ev === 'play' || ev === 'playing') current = el;
            if (el === current) post(ev !== 'timeupdate');
          }, true);
        });
      }
      function scan() { document.querySelectorAll('video,audio').forEach(attach); }
      new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
      scan();
      window.__aero = {
        toggle: function () { if (current) { current.paused ? current.play() : current.pause(); } },
        back10: function () { if (current) current.currentTime = Math.max(0, current.currentTime - 10); },
        fwd10: function () { if (current) current.currentTime = current.currentTime + 10; },
        pip: function () { if (current && current.webkitSetPresentationMode) current.webkitSetPresentationMode('picture-in-picture'); }
      };
    })();
    """
}
