import Foundation

extension AppModel {
    func resolveYouTubeV2(_ source: URL) async throws -> [DownloadMedia] {
        guard let id = youtubeVideoIDV2(source) else { throw AppError.message("رابط YouTube غير معروف") }

        let clients: [YTClientV2] = [
            .init(name: "ANDROID_VR", version: "1.71.26", key: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", userAgent: "com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12; en_US; Oculus Quest 3) gzip", clientID: "28", extra: ["osName":"Android","osVersion":"12","deviceMake":"Oculus","deviceModel":"Quest 3"]),
            .init(name: "ANDROID", version: "20.10.38", key: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w", userAgent: "com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip", clientID: "3", extra: ["osName":"Android","osVersion":"11"]),
            .init(name: "TVHTML5", version: "4", key: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version", clientID: "7", extra: [:]),
            .init(name: "IOS", version: "21.26.4", key: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8", userAgent: "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)", clientID: "5", extra: ["osName":"iPhone","osVersion":"18.3.2.22D82","deviceMake":"Apple","deviceModel":"iPhone16,2"])
        ]

        for client in clients {
            if let media = try? await innertubePlayerV2(videoID: id, client: client), !media.isEmpty { return media }
        }
        if let legacy = try? await resolveYouTube(source), !legacy.isEmpty { return legacy }
        throw AppError.message("تعذر جلب هذا الفيديو من YouTube")
    }

    private func innertubePlayerV2(videoID: String, client: YTClientV2) async throws -> [DownloadMedia] {
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(client.key)&prettyPrint=false") else { throw AppError.message("تعذر تجهيز YouTube") }

        var clientContext: [String: Any] = ["clientName": client.name, "clientVersion": client.version, "hl": "en", "gl": "US", "timeZone": "UTC", "utcOffsetMinutes": 0, "userAgent": client.userAgent]
        for (key, value) in client.extra { clientContext[key] = value }
        let body: [String: Any] = ["context": ["client": clientContext], "videoId": videoID, "contentCheckOk": true, "racyCheckOk": true, "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]]]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 18
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(client.clientID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
        if let p = json["playabilityStatus"] as? [String: Any], let status = p["status"] as? String, status != "OK" { throw AppError.message((p["reason"] as? String) ?? "YouTube: \(status)") }
        guard let streaming = json["streamingData"] as? [String: Any] else { return [] }

        let details = json["videoDetails"] as? [String: Any]
        let title = sanitize((details?["title"] as? String) ?? "youtube-\(videoID)")
        let thumb = ((details?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.last
        var output: [DownloadMedia] = []

        for f in streaming["formats"] as? [[String: Any]] ?? [] {
            guard let direct = f["url"] as? String, let url = URL(string: direct) else { continue }
            let mime = (f["mimeType"] as? String ?? "").lowercased()
            guard mime.contains("video/mp4") || mime.contains("video/") else { continue }
            let q = (f["qualityLabel"] as? String) ?? (f["quality"] as? String) ?? "فيديو"
            output.append(DownloadMedia(url: url, filename: "\(title)-\(q).mp4", type: "video", thumb: thumb, referer: "https://www.youtube.com/", platform: .youtube, quality: q, estimatedSize: ytInt64V2(f["contentLength"]), hasAudio: true))
        }

        let adaptive = streaming["adaptiveFormats"] as? [[String: Any]] ?? []
        let audioCandidates = adaptive.compactMap { f -> (URL, Int64?, Int, Int)? in
            guard let direct = f["url"] as? String, let url = URL(string: direct) else { return nil }
            let mime = (f["mimeType"] as? String ?? "").lowercased()
            guard mime.contains("audio/mp4") else { return nil }
            let bitrate = f["bitrate"] as? Int ?? 0
            let codecScore = mime.contains("mp4a.40.2") ? 3 : (mime.contains("mp4a") ? 2 : 1)
            return (url, ytInt64V2(f["contentLength"]), bitrate, codecScore)
        }
        let bestAudio = audioCandidates.max { lhs, rhs in
            if lhs.3 != rhs.3 { return lhs.3 < rhs.3 }
            return lhs.2 < rhs.2
        }

        if let bestAudio {
            let videos = adaptive.sorted { a, b in
                let ma = (a["mimeType"] as? String ?? "").lowercased()
                let mb = (b["mimeType"] as? String ?? "").lowercased()
                let pa = ytVideoCodecPriorityV2(ma)
                let pb = ytVideoCodecPriorityV2(mb)
                if pa != pb { return pa > pb }
                return (a["bitrate"] as? Int ?? 0) > (b["bitrate"] as? Int ?? 0)
            }

            for f in videos {
                guard let direct = f["url"] as? String, let videoURL = URL(string: direct) else { continue }
                let mime = (f["mimeType"] as? String ?? "").lowercased()
                guard mime.contains("video/mp4"), let q = f["qualityLabel"] as? String else { continue }
                let height = ytQualityNumberV2(q)
                guard height >= 720 else { continue }
                let videoSize = ytInt64V2(f["contentLength"])
                let total = (videoSize ?? 0) + (bestAudio.1 ?? 0)
                let codec = mime.contains("avc1") ? "H.264" : (mime.contains("hvc1") || mime.contains("hev1") ? "HEVC" : (mime.contains("av01") ? "AV1" : "MP4"))
                let label = q + (height >= 1080 ? " • HQ • \(codec)" : " • \(codec)")
                let media = DownloadMedia(url: videoURL, filename: "\(title)-\(q).mp4", type: "video", thumb: thumb, referer: "https://www.youtube.com/", platform: .youtube, quality: label, estimatedSize: total > 0 ? total : nil, hasAudio: false)
                YTCompanionStore.shared.setAudio(bestAudio.0, for: videoURL)
                output.append(media)
            }
        }

        var byQuality: [Int: DownloadMedia] = [:]
        for item in output {
            let n = ytQualityNumberV2(item.quality)
            if let old = byQuality[n] {
                let newScore = ytMediaPriorityV2(item)
                let oldScore = ytMediaPriorityV2(old)
                if newScore > oldScore { byQuality[n] = item }
            } else {
                byQuality[n] = item
            }
        }
        return byQuality.values.sorted { ytQualityNumberV2($0.quality) > ytQualityNumberV2($1.quality) }.prefix(8).map { $0 }
    }

    private func ytVideoCodecPriorityV2(_ mime: String) -> Int {
        if mime.contains("avc1") { return 4 }
        if mime.contains("hvc1") || mime.contains("hev1") { return 3 }
        if mime.contains("av01") { return 2 }
        return 1
    }

    private func ytMediaPriorityV2(_ item: DownloadMedia) -> Int {
        if item.quality.contains("H.264") { return 50 }
        if item.quality.contains("HEVC") { return 40 }
        if item.hasAudio { return 30 }
        if item.quality.contains("AV1") { return 20 }
        return 10
    }

    private func youtubeVideoIDV2(_ url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        if host.contains("youtu.be") { return url.pathComponents.dropFirst().first?.split(separator: "?").first.map(String.init) }
        if let c = URLComponents(url: url, resolvingAgainstBaseURL: false), let value = c.queryItems?.first(where: { $0.name == "v" })?.value, !value.isEmpty { return String(value.prefix(11)) }
        let parts = url.pathComponents
        if let index = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), index + 1 < parts.count { return String(parts[index + 1].split(separator: "?").first?.prefix(11) ?? Substring(parts[index + 1].prefix(11))) }
        return nil
    }

    private func ytQualityNumberV2(_ text: String) -> Int { Int(text.prefix { $0.isNumber }) ?? Int(text.filter(\.isNumber).prefix(4)) ?? 0 }
    private func ytInt64V2(_ value: Any?) -> Int64? { if let s = value as? String { return Int64(s) }; if let n = value as? NSNumber { return n.int64Value }; return nil }
}

private struct YTClientV2 {
    let name: String; let version: String; let key: String; let userAgent: String; let clientID: String; let extra: [String: String]
}
