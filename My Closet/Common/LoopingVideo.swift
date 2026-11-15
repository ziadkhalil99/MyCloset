import AVFoundation
import SwiftUI

/// A muted video that loops forever and fills its frame. It fades in once the first frame is
/// ready (no black flash), resumes when the app comes back to the foreground, and reports the
/// playhead about ten times a second through `onTime` so captions can follow along.
struct LoopingVideo: UIViewRepresentable {
    let url: URL
    var onTime: (Double) -> Void = { _ in }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.onTime = onTime
        view.start(url: url)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.onTime = onTime
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var onTime: (Double) -> Void = { _ in }

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var timeObserver: Any?
        private var readyObservation: NSKeyValueObservation?
        private var foregroundObserver: NSObjectProtocol?

        func start(url: URL) {
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            alpha = 0

            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor in
                    UIView.animate(withDuration: 0.35) { self?.alpha = 1 }
                }
            }
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
                MainActor.assumeIsolated { self?.onTime(time.seconds) }
            }
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.player.play() }
            }
            player.play()
        }

        func stop() {
            player.pause()
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
            timeObserver = nil
            foregroundObserver = nil
            readyObservation = nil
            looper?.disableLooping()
            looper = nil
        }
    }
}
