import SwiftUI
import AVKit

public struct TapoRecordingsTimelineView: View {
    public let camera: TapoCameraConfig

    @State private var clips: [TapoRecordingClip] = []
    @State private var selectedClip: TapoRecordingClip?
    @State private var selectedDate: Date = Date()
    @State private var isLoadingClips: Bool = false
    @State private var isLoadingPlayback: Bool = false
    @State private var playbackLoadProgress: Double = 0.0
    @State private var playbackStatusText: String = ""
    @State private var scrubPosition: Double = 0.0
    @State private var isDownloading: Bool = false
    @State private var downloadStatus: String = ""
    @State private var player: AVPlayer?
    @State private var playerTimeObserver: Any?
    @State private var eventCountLabel: String = ""

    // Filter state
    @State private var filterCode: Int = 0 // 0 = All

    public init(camera: TapoCameraConfig) {
        self.camera = camera
    }

    // MARK: - Derived

    private var filteredClips: [TapoRecordingClip] {
        guard filterCode != 0 else { return clips }
        return clips.filter { $0.eventCode == filterCode }
    }

    private var eventTypeGroups: [(code: Int, label: String, icon: String, count: Int)] {
        var counts: [Int: (label: String, icon: String, count: Int)] = [:]
        for clip in clips {
            if let existing = counts[clip.eventCode] {
                counts[clip.eventCode] = (existing.label, existing.icon, existing.count + 1)
            } else {
                counts[clip.eventCode] = (clip.eventType, clip.iconName, 1)
            }
        }
        return counts.map { (code: $0.key, label: $0.value.label, icon: $0.value.icon, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if !eventTypeGroups.isEmpty {
                filterChips
                Divider()
            }
            videoPlayerArea
            scrubberBar
            Divider()
            clipList
        }
        .onAppear { loadRecordings() }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack(spacing: 10) {
            DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .onChange(of: selectedDate) { _ in loadRecordings() }

            if !eventCountLabel.isEmpty {
                Text(eventCountLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isLoadingClips {
                ProgressView().controlSize(.small)
            }

            Button { loadRecordings() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
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
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(code: 0, label: "All", icon: "list.bullet", count: clips.count)
                ForEach(eventTypeGroups, id: \.code) { group in
                    filterChip(code: group.code, label: group.label, icon: group.icon, count: group.count)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.primary.opacity(0.02))
    }

    private func filterChip(code: Int, label: String, icon: String, count: Int) -> some View {
        let isSelected = filterCode == code
        return Button {
            withAnimation(.spring(response: 0.2)) { filterCode = code }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                Text("(\(count))")
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? badgeSwiftUIColor(for: code).opacity(0.85) : Color.primary.opacity(0.07))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var videoPlayerArea: some View {
        ZStack {
            Color.black

            if let p = player {
                VideoPlayer(player: p)
                    .onAppear { p.play() }
            } else if let clip = selectedClip {
                VStack(spacing: 8) {
                    Image(systemName: clip.iconName)
                        .font(.system(size: 44))
                        .foregroundStyle(badgeSwiftUIColor(for: clip.eventCode))
                    Text("Recording: \(clip.timeRangeString)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    eventBadge(clip: clip, size: .large)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "sdcard")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Select a clip to play & scrub")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Loading overlay
            if isLoadingPlayback {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(playbackStatusText.isEmpty ? "Buffering SD recording..." : playbackStatusText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(spacing: 4) {
                        ProgressView(value: playbackLoadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(width: 220)
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

            // Save overlay
            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.regular)
                    Text(downloadStatus)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.85)))
            }
        }
        .frame(height: 240)
    }

    private var scrubberBar: some View {
        VStack(spacing: 6) {
            HStack {
                if let clip = selectedClip {
                    HStack(spacing: 6) {
                        Image(systemName: clip.iconName)
                            .font(.system(size: 11))
                            .foregroundStyle(badgeSwiftUIColor(for: clip.eventCode))
                        Text(clip.timeRangeString)
                            .font(.system(size: 11, weight: .bold))
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(clip.eventType)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(badgeSwiftUIColor(for: clip.eventCode))
                    }
                } else {
                    Text("No Clip Selected")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let clip = selectedClip {
                    Text("\(clip.duration / 60)m \(clip.duration % 60)s")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

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
    }

    private var clipList: some View {
        Group {
            if filteredClips.isEmpty && !isLoadingClips {
                VStack(spacing: 8) {
                    Image(systemName: filterCode == 0 ? "sdcard" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(filterCode == 0 ? "No recordings found for this date" : "No \(filterCodeLabel) clips for this date")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredClips) { clip in
                    clipRow(clip)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedClip = clip
                            loadClipVideo(clip)
                        }
                }
                .listStyle(.inset)
            }
        }
    }

    private func clipRow(_ clip: TapoRecordingClip) -> some View {
        let isSelected = selectedClip?.id == clip.id
        return HStack(spacing: 10) {
            // Coloured indicator dot
            Circle()
                .fill(badgeSwiftUIColor(for: clip.eventCode))
                .frame(width: 9, height: 9)

            // Event icon
            Image(systemName: clip.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(badgeSwiftUIColor(for: clip.eventCode))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.timeRangeString)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))

                HStack(spacing: 4) {
                    Text(clip.eventType)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(badgeSwiftUIColor(for: clip.eventCode))
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(clip.duration >= 60 ? "\(clip.duration / 60)m \(clip.duration % 60)s" : "\(clip.duration)s")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: isLoadingPlayback ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? badgeSwiftUIColor(for: clip.eventCode).opacity(0.08) : Color.clear)
        )
    }

    private func eventBadge(clip: TapoRecordingClip, size: BadgeSize) -> some View {
        HStack(spacing: 4) {
            Image(systemName: clip.iconName)
                .font(.system(size: size == .large ? 12 : 10, weight: .semibold))
            Text(clip.eventType)
                .font(.system(size: size == .large ? 12 : 10, weight: .semibold))
        }
        .padding(.horizontal, size == .large ? 10 : 6)
        .padding(.vertical, size == .large ? 5 : 3)
        .background(
            Capsule().fill(badgeSwiftUIColor(for: clip.eventCode).opacity(0.85))
        )
        .foregroundStyle(.white)
    }

    // MARK: - Helpers

    private var filterCodeLabel: String {
        eventTypeGroups.first(where: { $0.code == filterCode })?.label ?? "event"
    }

    private func badgeSwiftUIColor(for code: Int) -> Color {
        switch code {
        case 6:         return .purple
        case 9:         return .green
        case 8:         return Color(red: 0.2, green: 0.5, blue: 1.0)
        case 5, 3, 13:  return .red
        case 4:         return Color(red: 0.0, green: 0.85, blue: 0.95)
        case 7, 11, 12: return Color(red: 1.0, green: 0.4, blue: 0.7)
        case 10:        return .yellow
        case 2:         return .orange
        default:        return Color.secondary
        }
    }

    private enum BadgeSize { case small, large }

    // MARK: - Actions

    private func loadRecordings() {
        isLoadingClips = true
        eventCountLabel = ""
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let dateStr = df.string(from: selectedDate)

        Task {
            let (res, evCount) = await TapoCameraService.shared.fetchRecordingsWithEventCount(camera: camera, dateString: dateStr)
            await MainActor.run {
                self.clips = res
                self.filterCode = 0 // reset filter on new date
                self.isLoadingClips = false
                if let count = evCount, count > 0 {
                    self.eventCountLabel = "\(res.count) clips • \(count) events"
                } else {
                    self.eventCountLabel = "\(res.count) clips"
                }
                if let firstClip = res.first {
                    self.selectedClip = firstClip
                    loadClipVideo(firstClip)
                }
            }
        }
    }

    private func loadClipVideo(_ clip: TapoRecordingClip) {
        guard let url = Go2rtcServerManager.shared.mp4RecordURL(for: camera.id, durationSeconds: min(120, clip.duration)) else {
            return
        }

        isLoadingPlayback = true
        playbackLoadProgress = 0.05
        playbackStatusText = "Connecting to camera SD stream..."

        if let observer = playerTimeObserver {
            player?.removeTimeObserver(observer)
            playerTimeObserver = nil
        }
        player?.pause()
        player = nil

        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)

        // Progress simulation during buffer init
        Task {
            let steps = ["Connecting to camera SD stream...", "Fetching recording buffer from SD...", "Decoding video stream...", "Buffering..."]
            for (i, step) in steps.enumerated() {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    if self.isLoadingPlayback {
                        self.playbackLoadProgress = min(0.85, Double(i + 1) * 0.20 + 0.05)
                        self.playbackStatusText = step
                    }
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        playerTimeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if let duration = newPlayer.currentItem?.duration.seconds, duration > 0, !duration.isNaN {
                self.scrubPosition = time.seconds / duration
            }
        }

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
            // Fallback
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.isDownloading = false }
                }
            } catch {
                await MainActor.run {
                    self.downloadStatus = "Error: \(error.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.isDownloading = false }
                }
            }
        }
    }
}
