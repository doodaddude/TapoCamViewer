import SwiftUI
import AVKit

public struct TapoRecordingsTimelineView: View {
    public let camera: TapoCameraConfig
    @State private var clips: [TapoRecordingClip] = []
    @State private var selectedClip: TapoRecordingClip?
    @State private var selectedDate: Date = Date()
    @State private var isLoadingClips: Bool = false
    @State private var isLoadingPlayback: Bool = false
    @State private var playbackLoadProgress: Double = 0.0 // 0.0 to 1.0
    @State private var playbackStatusText: String = ""
    @State private var scrubPosition: Double = 0.0 // 0.0 ... 1.0 within clip
    @State private var isDownloading: Bool = false
    @State private var downloadStatus: String = ""
    @State private var player: AVPlayer?
    @State private var playerTimeObserver: Any?

    public init(camera: TapoCameraConfig) {
        self.camera = camera
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header / Date Picker
            HStack {
                DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: selectedDate) { _ in
                        loadRecordings()
                    }

                Spacer()

                if isLoadingClips {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button {
                    loadRecordings()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh SD Clips")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingClips)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))

            Divider()

            // Video Player / Preview Area
            ZStack {
                Color.black

                if let p = player {
                    VideoPlayer(player: p)
                        .onAppear { p.play() }
                } else if let clip = selectedClip {
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                        Text("Recording: \(clip.timeRangeString)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(clip.isMotion ? "Motion Detection Event" : "Continuous SD Recording")
                            .font(.system(size: 11))
                            .foregroundStyle(clip.isMotion ? Color.orange : Color.gray)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "sdcard")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Select a clip on the timeline below to play & scrub")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                // Loading Playback Progress Bar Overlay
                if isLoadingPlayback {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(playbackStatusText.isEmpty ? "Buffering SD recording..." : playbackStatusText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        // Determinate Progress Bar
                        VStack(spacing: 4) {
                            ProgressView(value: playbackLoadProgress, total: 1.0)
                                .progressViewStyle(.linear)
                                .frame(width: 200)
                                .tint(Color(red: 0.0, green: 0.85, blue: 0.95))

                            Text("\(Int(playbackLoadProgress * 100))%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.5), radius: 10)
                    )
                }

                // Saving / Exporting Clip Overlay
                if isDownloading {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(downloadStatus)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.85)))
                }
            }
            .frame(height: 240)

            // Timeline Scrubbing Bar
            VStack(spacing: 6) {
                HStack {
                    Text(selectedClip?.timeRangeString ?? "No Clip Selected")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    if let clip = selectedClip {
                        Text("\(clip.duration / 60) min \(clip.duration % 60) sec")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                // Interactive Scrubber Slider
                Slider(value: $scrubPosition, in: 0...1) { editing in
                    if !editing, let p = player, let currentItem = p.currentItem {
                        let totalDuration = currentItem.duration.seconds
                        if totalDuration > 0 && !totalDuration.isNaN {
                            let targetTime = CMTime(seconds: totalDuration * scrubPosition, preferredTimescale: 600)
                            p.seek(to: targetTime)
                        }
                    }
                }
                .controlSize(.small)
                .disabled(selectedClip == nil)

                // Actions: Save to Local Storage / Open Folder
                HStack {
                    Button {
                        saveCurrentClip()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Save Clip to Mac")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(selectedClip == nil || isDownloading)

                    Button("Open Recordings Folder") {
                        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
                        let tapoDir = movies.appendingPathComponent("TapoRecordings", isDirectory: true)
                        try? FileManager.default.createDirectory(at: tapoDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(tapoDir)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))

            Divider()

            // List of Clips for the Day
            List(clips) { clip in
                HStack(spacing: 10) {
                    Circle()
                        .fill(clip.isMotion ? Color.orange : Color.blue)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.timeRangeString)
                            .font(.system(size: 12, weight: selectedClip?.id == clip.id ? .bold : .medium))
                        Text(clip.isMotion ? "Motion Event • \(clip.duration)s" : "Continuous • \(clip.duration / 60)m")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selectedClip?.id == clip.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedClip = clip
                    loadClipVideo(clip)
                }
            }
            .listStyle(.inset)
        }
        .onAppear {
            loadRecordings()
        }
    }

    private func loadRecordings() {
        isLoadingClips = true
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let dateStr = df.string(from: selectedDate)

        Task {
            let res = await TapoCameraService.shared.fetchRecordings(camera: camera, dateString: dateStr)
            await MainActor.run {
                self.clips = res
                self.selectedClip = res.first
                self.isLoadingClips = false
                if let firstClip = res.first {
                    loadClipVideo(firstClip)
                }
            }
        }
    }

    private func loadClipVideo(_ clip: TapoRecordingClip) {
        guard let url = Go2rtcServerManager.shared.mp4RecordURL(for: camera.id, durationSeconds: min(120, clip.duration)) else {
            return
        }

        // Show Loading Progress Bar
        isLoadingPlayback = true
        playbackLoadProgress = 0.05
        playbackStatusText = "Connecting to camera SD stream..."

        // Clean up previous player
        if let observer = playerTimeObserver {
            player?.removeTimeObserver(observer)
            playerTimeObserver = nil
        }
        player?.pause()
        player = nil

        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)

        // Progress simulation during buffer initialization
        Task {
            for step in 1...8 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    if self.isLoadingPlayback {
                        self.playbackLoadProgress = min(0.85, self.playbackLoadProgress + 0.10)
                        if step == 3 {
                            self.playbackStatusText = "Fetching recording buffer from SD..."
                        } else if step == 6 {
                            self.playbackStatusText = "Decoding video stream..."
                        }
                    }
                }
            }
        }

        // Periodic observer for timeline scrub position
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        playerTimeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if let duration = newPlayer.currentItem?.duration.seconds, duration > 0, !duration.isNaN {
                self.scrubPosition = time.seconds / duration
            }
        }

        // Check buffer readiness
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if playerItem.status == .readyToPlay || (playerItem.loadedTimeRanges.first?.timeRangeValue.duration.seconds ?? 0) > 0 {
                    await MainActor.run {
                        self.playbackLoadProgress = 1.0
                        self.playbackStatusText = "Playing..."
                        self.player = newPlayer
                        newPlayer.play()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.isLoadingPlayback = false
                        }
                    }
                    return
                }
            }

            // Fallback: start playing anyway
            await MainActor.run {
                self.playbackLoadProgress = 1.0
                self.player = newPlayer
                newPlayer.play()
                self.isLoadingPlayback = false
            }
        }
    }

    private func saveCurrentClip() {
        guard let clip = selectedClip else { return }
        guard let url = Go2rtcServerManager.shared.mp4RecordURL(for: camera.id, durationSeconds: max(10, clip.duration)) else { return }

        isDownloading = true
        downloadStatus = "Saving clip to ~/Movies/TapoRecordings..."

        Task {
            do {
                let name = "\(camera.name.replacingOccurrences(of: " ", with: "_"))_\(clip.startTime)"
                let saved = try await TapoCameraService.shared.saveClipLocally(from: url, suggestedName: name)
                await MainActor.run {
                    self.downloadStatus = "Saved: \(saved.lastPathComponent)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.isDownloading = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.downloadStatus = "Error saving clip: \(error.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.isDownloading = false
                    }
                }
            }
        }
    }
}
