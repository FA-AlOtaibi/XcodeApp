import Foundation

extension AppModel {
    func resolveYouTubeV2(_ source: URL) async throws -> [DownloadMedia] {
        guard let id = youtubeVideoIDV2(source) else {
            throw AppError.message("رابط YouTube غير معروف")
        }

        // First try YouTube's own Innertube player API with clients that can
        // return direct progressive streams. This avoids depending on public
        // Piped/Invidious instances for Shorts.
        let clients: [YTClientV2] = [
            .init(
                name: "ANDROID_VR",
                version: "1.71.26",
                key: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
                userAgent: "com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12; en_US; Oculus Quest 3) gzip",
                clientID: "28",
                extra: [
                    "osName": "Android",
                    "osVersion": "12",
                    "deviceMake": "Oculus",
                    "deviceModel": "Quest 3"
                ]
            ),
            .init(
                name: "ANDROID",
                version: "20.10.38",
                key: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w",
                userAgent: "com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip",
                clientID: "3",
                extra: [
                    "osName": "Android",
                    "osVersion": "11"
                ]
            ),
            .init(
                name: "TVHTML5",
                version: "4",
                key: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
                userAgent: "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version",
                clientID: "7",
                extra: [:]
            ),
            .init(
                name: "IOS",
                version: "21.26.4",
                key: "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
                userAgent: "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
                clientID: "5",
                extra: [
                    "osName": "iPhone",
                    "osVersion": "18.3.2.22D82",
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2"
                ]
            )
        ]

        for client in clients {
            if let media = try? await innertubePlayerV2(videoID: id, client: client), !media.isEmpty {
                return media
            }
        }

        // Keep the old resolver as a final fallback for cases where a public
        // frontend happens to have a usable progressive stream.
        if let legacy = try? await resolveYouTube(source), !legacy.isEmpty {
            return legacy
        }

        throw AppError.message("تعذر جلب هذا الفيديو من YouTube")
    }

    private func innertubePlayerV2(videoID: String, client: YTClientV2) async throws -> [DownloadMedia] {
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(client.key)&prettyPrint=false") else {
            throw AppError.message("تعذر تجهيز YouTube")
        }

        var clientContext: [String: Any] = [
            "clientName": client.name,
            "clientVersion": client.version,
            "hl": "en",
            "gl": "US",
            "timeZone": "UTC",
            "utcOffsetMinutes": 0,
            "userAgent": client.userAgent
        ]
        for (key, value) in client.extra { clientContext[key] = value }

        let body: [String: Any] = [
            "context": ["client": clientContext],
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(client.clientID, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }

        if let playability = json["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK" {
            throw AppError.message((playability["reason"] as? String) ?? "YouTube: \(status)")
        }

        guard let streaming = json["streamingData"] as? [String: Any] else {
            return []
        }

        let details = json["videoDetails"] as? [String: Any]
        let rawTitle = (details?["title"] as? String) ?? "youtube-\(videoID)"
        let title = sanitize(rawTitle)
        let thumb = ((details?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
            .compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }
            .last

        var output: [DownloadMedia] = []

        // `formats` are progressive streams (video + audio) when supplied by
        // the client, which is what the iOS app can download/play directly.
        let progressive = streaming["formats"] as? [[String: Any]] ?? []
        for format in progressive {
            guard let direct = format["url"] as? String, let url = URL(string: direct) else { continue }
            let mime = (format["mimeType"] as? String ?? "").lowercased()
            guard mime.contains("video/mp4") || mime.contains("video/") else { continue }
            let q = (format["qualityLabel"] as? String) ?? (format["quality"] as? String) ?? "فيديو"
            let size = ytInt64V2(format["contentLength"])
            output.append(
                DownloadMedia(
                    url: url,
                    filename: "\(title)-\(q).mp4",
                    type: "video",
                    thumb: thumb,
                    referer: "https://www.youtube.com/",
                    platform: .youtube,
                    quality: q,
                    estimatedSize: size,
                    hasAudio: true
                )
            )
        }

        if !output.isEmpty {
            return Array(output.sorted { ytQualityNumberV2($0.quality) > ytQualityNumberV2($1.quality) }.prefix(5))
        }

        // Some clients expose direct adaptive streams only. Keep only streams
        // which explicitly include audio+video; otherwise the downloaded file
        // would be silent and misleading to the user.
        let adaptive = streaming["adaptiveFormats"] as? [[String: Any]] ?? []
        for format in adaptive {
            guard let direct = format["url"] as? String, let url = URL(string: direct) else { continue }
            let mime = (format["mimeType"] as? String ?? "").lowercased()
            guard mime.contains("video/") else { continue }
            let hasAudio = format["audioQuality"] != nil || mime.contains("audio/")
            guard hasAudio else { continue }
            let q = (format["qualityLabel"] as? String) ?? "فيديو"
            output.append(
                DownloadMedia(
                    url: url,
                    filename: "\(title)-\(q).mp4",
                    type: "video",
                    thumb: thumb,
                    referer: "https://www.youtube.com/",
                    platform: .youtube,
                    quality: q,
                    estimatedSize: ytInt64V2(format["contentLength"]),
                    hasAudio: true
                )
            )
        }

        return Array(output.sorted { ytQualityNumberV2($0.quality) > ytQualityNumberV2($1.quality) }.prefix(5))
    }

    private func youtubeVideoIDV2(_ url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        if host.contains("youtu.be") {
            return url.pathComponents.dropFirst().first?.split(separator: "?").first.map(String.init)
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !value.isEmpty {
            return String(value.prefix(11))
        }
        let parts = url.pathComponents
        if let index = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), index + 1 < parts.count {
            let raw = parts[index + 1]
            return String(raw.split(separator: "?").first?.prefix(11) ?? Substring(raw.prefix(11)))
        }
        return nil
    }

    private func ytQualityNumberV2(_ text: String) -> Int {
        Int(text.filter(\.isNumber)) ?? 0
    }

    private func ytInt64V2(_ value: Any?) -> Int64? {
        if let string = value as? String { return Int64(string) }
        if let number = value as? NSNumber { return number.int64Value }
        return nil
    }
}

private struct YTClientV2 {
    let name: String
    let version: String
    let key: String
    let userAgent: String
    let clientID: String
    let extra: [String: String]
}
