import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CarMediaCore

final class XtreamClientTests: XCTestCase {
    private let fixtures: [String: String] = [
        "": "xtream_account.json",
        "get_live_categories": "xtream_live_categories.json",
        "get_live_streams": "xtream_live_streams.json",
        "get_vod_streams": "xtream_vod_streams.json",
        "get_series": "xtream_series.json",
        "get_series_info": "xtream_series_info.json",
        "get_vod_info": "xtream_vod_info.json",
        "get_short_epg": "xtream_short_epg.json",
        "get_simple_data_table": "xtream_short_epg.json",
    ]

    private func client(_ transport: StubTransport, password: String = "s3cret+pass") throws -> XtreamClient {
        XtreamClient(
            credentials: try XtreamCredentials(baseURL: "http://iptv.example.com:8080", username: "demo", password: password),
            transport: transport
        )
    }

    private func fixtureClient() throws -> (XtreamClient, StubTransport) {
        let transport = StubTransport.xtream(fixtures: fixtures)
        return (try client(transport), transport)
    }

    // MARK: Account

    func testAccountInfoForConnectionTestScreen() async throws {
        let (client, _) = try fixtureClient()
        let info = try await client.accountInfo()
        let user = try XCTUnwrap(info.userInfo)
        XCTAssertEqual(user.auth, true)
        XCTAssertEqual(user.status, "Active")
        XCTAssertTrue(user.isActive)
        XCTAssertEqual(user.expDate, 1_798_761_600)
        XCTAssertEqual(user.expirationDate, Date(timeIntervalSince1970: 1_798_761_600))
        XCTAssertEqual(user.maxConnections, 2)
        XCTAssertEqual(user.activeConnections, 1)
        XCTAssertEqual(user.isTrial, false)
        XCTAssertTrue(user.supportsHLS)
        let server = try XCTUnwrap(info.serverInfo)
        XCTAssertEqual(server.url, "iptv.example.com")
        XCTAssertEqual(server.port, 8080)
        XCTAssertEqual(server.httpsPort, 8443)
        XCTAssertNil(server.rtmpPort)
        XCTAssertEqual(server.timezone, "Europe/Istanbul")
        XCTAssertEqual(server.timestampNow, 1_790_100_000)
    }

    func testAuthFailureObjectThrows() async throws {
        let transport = StubTransport { _ in (200, try Fixture.data("xtream_auth_failed.json"), [:]) }
        let client = try client(transport)
        await assertThrowsAsync(.authenticationFailed) { try await client.accountInfo() }
        await assertThrowsAsync(.authenticationFailed) { try await client.liveStreams() }
    }

    func testEmptyArrayAccountResponseMeansBadCredentials() async throws {
        let client = try client(StubTransport { _ in (200, Data("[]".utf8), [:]) })
        await assertThrowsAsync(.authenticationFailed) { try await client.accountInfo() }
        let streams = try await client.liveStreams()
        XCTAssertTrue(streams.isEmpty)
    }

    func testHTTPStatusMapping() async throws {
        let failing = try client(StubTransport { _ in (503, Data(), [:]) })
        await assertThrowsAsync(.httpStatus(503)) { try await failing.liveCategories() }
        let forbidden = try client(StubTransport { _ in (403, Data(), [:]) })
        await assertThrowsAsync(.authenticationFailed) { try await forbidden.liveCategories() }
    }

    func testTransportErrorsAreRedacted() async throws {
        struct Boom: Error, CustomStringConvertible {
            let description = "connection reset for http://iptv.example.com:8080/player_api.php?username=demo&password=s3cret%2Bpass"
        }
        let client = try client(StubTransport { _ in throw Boom() })
        do {
            _ = try await client.liveCategories()
            XCTFail("expected an error")
        } catch let CarMediaError.transport(message) {
            XCTAssertFalse(message.contains("s3cret"), message)
            XCTAssertTrue(message.contains(Redaction.placeholder))
        }
    }

    func testDecodingErrorsAreRedacted() async throws {
        let client = try client(StubTransport { _ in (200, Data("{\"s3cret+pass\": ".utf8), [:]) })
        do {
            _ = try await client.vodInfo(vodID: 1)
            XCTFail("expected an error")
        } catch let CarMediaError.decoding(message) {
            XCTAssertFalse(message.contains("s3cret+pass"), message)
        }
    }

    // MARK: Catalog

    func testCategoriesToleratesMixedTypes() async throws {
        let (client, transport) = try fixtureClient()
        let categories = try await client.liveCategories()
        XCTAssertEqual(categories.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(categories.map(\.categoryName), ["Haber", "Spor", "Radyo"])
        XCTAssertEqual(categories.map(\.parentID), [0, 0, nil])
        let sent = try XCTUnwrap(transport.requests.first?.url?.absoluteString)
        XCTAssertTrue(sent.contains("action=get_live_categories"))
    }

    func testLiveStreamsSkipMalformedElementsAndCoerceTypes() async throws {
        let (client, _) = try fixtureClient()
        let streams = try await client.liveStreams(categoryID: "1")
        XCTAssertEqual(streams.count, 4) // the bare string element is skipped
        XCTAssertEqual(streams[0].streamID, 101)
        XCTAssertEqual(streams[0].tvArchive, true)
        XCTAssertEqual(streams[0].tvArchiveDuration, 3)
        XCTAssertEqual(streams[1].streamID, 102)
        XCTAssertEqual(streams[1].num, 2)
        XCTAssertEqual(streams[1].categoryID, "2")
        XCTAssertEqual(streams[1].tvArchive, false)
        XCTAssertNil(streams[1].epgChannelID)
        XCTAssertNil(streams[1].tvArchiveDuration)
        XCTAssertTrue(streams[2].isRadio)
        XCTAssertNil(streams[3].streamID)
    }

    func testLiveStreamsMapToChannels() async throws {
        let (client, _) = try fixtureClient()
        let channels = client.channels(from: try await client.liveStreams(), categories: try await client.liveCategories())
        XCTAssertEqual(channels.map(\.title), ["Örnek Haber", "Demo Spor", "Test Radyo"])
        XCTAssertEqual(channels[0].streamURL.absoluteString, "http://iptv.example.com:8080/live/demo/s3cret%2Bpass/101.m3u8")
        XCTAssertEqual(channels[0].groupTitle, "Haber")
        XCTAssertEqual(channels[0].tvgID, "ornek.haber")
        XCTAssertEqual(channels[0].catchup, "xc")
        XCTAssertNil(channels[1].logoURL)
        XCTAssertTrue(channels[2].isRadio)
        // Ids do not depend on the password.
        let other = try self.client(StubTransport.xtream(fixtures: fixtures), password: "different")
        let otherChannels = other.channels(from: try await other.liveStreams())
        XCTAssertEqual(channels.map(\.id), otherChannels.map(\.id))
    }

    func testVODStreamsRatingsAndExtensions() async throws {
        let (client, _) = try fixtureClient()
        let vod = try await client.vodStreams()
        XCTAssertEqual(vod.map(\.streamID), [2001, 2002])
        XCTAssertEqual(vod[0].rating, 7.4)
        XCTAssertEqual(vod[0].rating5Based, 3.7)
        XCTAssertNil(vod[0].customSID)
        XCTAssertNil(vod[1].rating)
        XCTAssertEqual(vod[1].rating5Based, 0)
        XCTAssertEqual(vod[1].containerExtension, "mkv")
    }

    func testSeriesListBackdropShapes() async throws {
        let (client, _) = try fixtureClient()
        let series = try await client.series()
        XCTAssertEqual(series.map(\.seriesID), [301, 302])
        XCTAssertEqual(series[0].backdropPath, ["http://img.example.com/series/uydurma-bg.jpg"])
        XCTAssertEqual(series[0].releaseDate, "2025-01-01")
        XCTAssertNil(series[1].backdropPath)
        XCTAssertNil(series[1].rating)
        XCTAssertEqual(series[1].categoryID, "21")
    }

    func testSeriesInfoEpisodesSorted() async throws {
        let (client, _) = try fixtureClient()
        let info = try await client.seriesInfo(seriesID: 301)
        XCTAssertEqual(info.seasons.map(\.seasonNumber), [1, 2])
        XCTAssertEqual(info.seasons.map(\.episodeCount), [2, 1])
        XCTAssertEqual(info.info?.name, "Uydurma Dizi")
        XCTAssertEqual(info.info?.rating, 8.1)
        XCTAssertEqual(info.sortedEpisodes.map(\.id), ["5001", "5002", "5003"])
        let first = info.sortedEpisodes[0]
        XCTAssertEqual(first.info?.durationSecs, 2640)
        XCTAssertNil(first.info?.rating)
        XCTAssertNil(info.sortedEpisodes[2].info) // "info": [] tolerated
        XCTAssertEqual(info.sortedEpisodes[1].season, 1)
    }

    func testSeriesInfoEpisodesAsArrayOfArrays() throws {
        let json = """
        {"seasons": [], "info": [], "episodes": [[{"id": "1", "episode_num": 1, "season": 3}], [{"id": "2", "episode_num": 1}]]}
        """
        let info = try JSONDecoder().decode(XtreamSeriesInfo.self, from: Data(json.utf8))
        XCTAssertNil(info.info)
        XCTAssertEqual(info.episodes["3"]?.map(\.id), ["1"])
        XCTAssertEqual(info.episodes["2"]?.map(\.id), ["2"])
    }

    func testVODInfoWithEmptyInfoArray() async throws {
        let (client, _) = try fixtureClient()
        let info = try await client.vodInfo(vodID: 2001)
        XCTAssertNil(info.info)
        XCTAssertEqual(info.movieData?.streamID, 2001)
        XCTAssertEqual(info.movieData?.containerExtension, "mp4")
    }

    // MARK: EPG

    func testShortEPGDecodesBase64AndTimestamps() async throws {
        let (client, transport) = try fixtureClient()
        let listings = try await client.shortEPG(streamID: 101, limit: 2)
        XCTAssertEqual(listings.count, 2)
        XCTAssertEqual(listings[0].decodedTitle, "Akşam Bülteni")
        XCTAssertEqual(listings[0].decodedDescription, "Günün özeti ve hava durumu.")
        XCTAssertEqual(listings[0].startDate, Date(timeIntervalSince1970: 1_790_100_000))
        XCTAssertEqual(listings[0].stopDate, Date(timeIntervalSince1970: 1_790_103_600))
        XCTAssertEqual(listings[0].nowPlaying, true)
        XCTAssertEqual(listings[0].hasArchive, false)
        // Missing base64 padding, no timestamps (falls back to "start" as UTC), empty description.
        XCTAssertEqual(listings[1].decodedTitle, "Gece Kuşağı")
        XCTAssertNil(listings[1].decodedDescription)
        XCTAssertEqual(listings[1].startDate, Date(timeIntervalSince1970: 1_790_103_600))
        let programme = try XCTUnwrap(listings[0].programme())
        XCTAssertEqual(programme.channelID, "ornek.haber")
        XCTAssertEqual(programme.title, "Akşam Bülteni")
        XCTAssertTrue(try XCTUnwrap(transport.requests.last?.url?.absoluteString).contains("limit=2"))
    }

    func testSimpleDataTableAndEmptyEPG() async throws {
        let (client, _) = try fixtureClient()
        let table = try await client.simpleDataTable(streamID: 101)
        XCTAssertEqual(table.count, 2)
        let empty = try self.client(StubTransport { _ in (200, Data("{\"epg_listings\": []}".utf8), [:]) })
        let none = try await empty.shortEPG(streamID: 1)
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: Lossy primitives

    func testLossyWrappersAcrossShapes() throws {
        struct Probe: Codable {
            @LossyInt var a: Int?
            @LossyInt var b: Int?
            @LossyInt var c: Int?
            @LossyInt var missing: Int?
            @LossyBool var d: Bool?
            @LossyBool var e: Bool?
            @LossyBool var f: Bool?
            @LossyString var g: String?
            @LossyDouble var h: Double?
            @LossyDouble var i: Double?
        }
        let json = #"{"a": "12", "b": "", "c": 3.0, "d": "yes", "e": 0, "f": "maybe", "g": 42, "h": "7,5", "i": null}"#
        let p = try JSONDecoder().decode(Probe.self, from: Data(json.utf8))
        XCTAssertEqual(p.a, 12)
        XCTAssertNil(p.b)
        XCTAssertEqual(p.c, 3)
        XCTAssertNil(p.missing)
        XCTAssertEqual(p.d, true)
        XCTAssertEqual(p.e, false)
        XCTAssertNil(p.f)
        XCTAssertEqual(p.g, "42")
        XCTAssertEqual(p.h, 7.5)
        XCTAssertNil(p.i)
        // Round-trips through encoding.
        let again = try JSONDecoder().decode(Probe.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(again.a, 12)
        XCTAssertEqual(again.g, "42")
    }
}
