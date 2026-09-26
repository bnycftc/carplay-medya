import CarMediaCore
import CarMediaKit
import SwiftUI

/// Programme guide: channels that have EPG data, with "now / next".
struct GuideView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @State private var query = ""

    private let presenter = GuidePresenter()

    private var channels: [Channel] {
        let withGuide = model.library.allChannels.filter { channel in
            guard let store = model.guide(for: channel) else { return false }
            return presenter.hasGuide(channel, in: store)
        }
        return model.library.filter(withGuide, query: query)
    }

    var body: some View {
        let channels = self.channels
        Group {
            if channels.isEmpty && query.isEmpty {
                ContentUnavailableView {
                    Label("Rehber yok", systemImage: "calendar")
                } description: {
                    Text("Kaynaklarınız program rehberi (EPG) sağlamıyor. M3U listesinde url-tvg adresi olmalı veya bir Xtream hesabı kullanılmalı.")
                }
            } else {
                TimelineView(.everyMinute) { context in
                    List {
                        if channels.isEmpty {
                            Text("Sonuç bulunamadı").foregroundStyle(.secondary)
                        }
                        ForEach(channels) { channel in
                            NavigationLink {
                                ChannelGuideView(channel: channel)
                            } label: {
                                HStack(spacing: 8) {
                                    ChannelRow(
                                        title: channel.title,
                                        logoURL: channel.logoURL,
                                        isRadio: channel.isRadio,
                                        summary: model.epgSummary(for: channel, at: context.date),
                                        isFavorite: model.isFavorite(channel.id),
                                        isCurrent: playback.state.channel?.id == channel.id
                                    )
                                    if CatchupURLBuilder.supportsCatchup(channel) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel(Text("Arşiv var"))
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Rehber")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Kanal ara"))
        .nowPlayingInset()
    }
}

/// One channel's schedule from yesterday to tomorrow; past programmes can be replayed when the channel has an archive.
struct ChannelGuideView: View {
    let channel: Channel
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @ObservedObject private var catalog = CatalogModel.shared
    @State private var expandedID: String?
    @State private var didScroll = false
    @State private var replayFailed = false
    @State private var loadingReplayID: String?

    private let presenter = GuidePresenter()

    var body: some View {
        TimelineView(.everyMinute) { context in
            let days = model.guide(for: channel).map {
                presenter.schedule(for: channel, in: $0, now: context.date)
            } ?? []
            ScrollViewReader { proxy in
                List {
                    if days.isEmpty {
                        Text("Bu kanal için program bilgisi yok.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(days) { day in
                        Section {
                            ForEach(day.entries) { entry in
                                row(entry)
                                    .id(entry.id)
                            }
                        } header: {
                            dayTitle(day)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    guard !didScroll, let live = GuidePresenter.liveEntry(in: days) else { return }
                    didScroll = true
                    DispatchQueue.main.async {
                        proxy.scrollTo(live.id, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: channel.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    playback.play(channel)
                } label: {
                    Label("Canlı izle", systemImage: "play.circle")
                }
            }
        }
        .alert("Bu program arşivden oynatılamıyor.", isPresented: $replayFailed) {
            Button("Tamam", role: .cancel) {}
        }
        .nowPlayingInset()
    }

    @ViewBuilder
    private func row(_ entry: GuideEntry) -> some View {
        let isExpanded = expandedID == entry.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: entry.timeRange)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(entry.state == .live ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 84, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.programme.title)
                        .font(.body.weight(entry.state == .live ? .semibold : .regular))
                        .foregroundStyle(entry.state == .past ? Color.secondary : Color.primary)
                        .lineLimit(isExpanded ? nil : 2)
                    if entry.state == .live {
                        ProgressView(value: entry.progress)
                            .progressViewStyle(.linear)
                    }
                    if isExpanded, let description = entry.programme.description, !description.isEmpty {
                        Text(verbatim: description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                actionButton(entry)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            expandedID = isExpanded ? nil : entry.id
        }
    }

    @ViewBuilder
    private func actionButton(_ entry: GuideEntry) -> some View {
        switch entry.state {
        case .live:
            Button {
                playback.play(channel)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Canlı izle"))
        case .past where entry.canReplay:
            if loadingReplayID == entry.id {
                ProgressView()
            } else {
                Button {
                    replay(entry)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Arşivden izle"))
            }
        default:
            EmptyView()
        }
    }

    private func replay(_ entry: GuideEntry) {
        loadingReplayID = entry.id
        Task {
            let archived = await catalog.catchupChannel(for: channel, programme: entry.programme)
            loadingReplayID = nil
            if let archived {
                playback.play(archived)
            } else {
                replayFailed = true
            }
        }
    }

    @ViewBuilder
    private func dayTitle(_ day: GuideDay) -> some View {
        switch day.dayOffset {
        case 0: Text("Bugün")
        case -1: Text("Dün")
        case 1: Text("Yarın")
        default: Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide))
        }
    }
}
