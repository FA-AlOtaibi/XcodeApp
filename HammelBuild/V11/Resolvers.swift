import Foundation

extension AppModel {
    func resolveTikTok(_ source: URL) async throws -> [DownloadMedia] {
        let (html, final) = try await fetchHTML(source, referer: "https://www.tiktok.com/")
        var roots:[Any] = []
        for p in [#"<script[^>]*id=[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>(.*?)</script>"#, #"<script[^>]*id=[\"']SIGI_STATE[\"'][^>]*>(.*?)</script>"#] {
            if let raw = regexFirst(html,p), let d = raw.data(using:.utf8), let obj = try? JSONSerialization.jsonObject(with:d) { roots.append(obj) }
        }
        for root in roots {
            let imgs = tikTokImages(root)
            if !imgs.isEmpty { let id = firstString(root, keys:["id","itemId","aweme_id"]) ?? "post"; return imgs.enumerated().map { i,u in DownloadMedia(url:u, filename:"tiktok-\(id)-\(i+1).jpg", type:"photo", thumb:u, referer:final.absoluteString, platform:.tiktok, quality:"صورة") } }
        }
        for root in roots {
            if let play = firstURL(root, keys:["playAddr","playAddrH264"]), let u = URL(string:play) {
                let cover = firstURL(root, keys:["cover","originCover"]).flatMap(URL.init(string:)); let id = firstString(root, keys:["id","itemId"]) ?? "video"
                return [DownloadMedia(url:u, filename:"tiktok-\(id).mp4", type:"video", thumb:cover, referer:"https://www.tiktok.com/", platform:.tiktok, quality:"أصلي")]
            }
        }
        if let raw = regexFirst(html,#"\"playAddr\"\s*:\s*\"([^\"]+)\""#), let u = URL(string:decodeEscapedURL(raw)) { return [DownloadMedia(url:u, filename:"tiktok-video.mp4", type:"video", thumb:nil, referer:final.absoluteString, platform:.tiktok)] }
        throw AppError.message("تعذر قراءة منشور TikTok")
    }

    func resolveYouTube(_ source: URL) async throws -> [DownloadMedia] {
        guard let id = youtubeID(source) else { throw AppError.message("رابط YouTube غير معروف") }
        // Shorts, youtu.be and watch URLs all normalize to the same video id here.
        if let p = try? await youtubePiped(id), !p.isEmpty { return p }
        if let i = try? await youtubeInvidious(id), !i.isEmpty { return i }
        if let w = try? await youtubeWatch(id), !w.isEmpty { return w }
        throw AppError.message("تعذر جلب فيديو YouTube الآن")
    }

    private func youtubePiped(_ id:String) async throws -> [DownloadMedia] {
        let hosts = ["https://pipedapi.kavin.rocks","https://pipedapi.tokhmi.xyz","https://pipedapi.moomoo.me","https://pipedapi.syncpundit.io","https://api-piped.mha.fi","https://piped-api.garudalinux.org"]
        for host in hosts {
            guard let endpoint = URL(string:"\(host)/streams/\(id)") else { continue }
            do {
                var r = URLRequest(url:endpoint); r.timeoutInterval = 8; r.setValue(ua,forHTTPHeaderField:"User-Agent")
                let (d,res) = try await URLSession.shared.data(for:r); guard let h=res as? HTTPURLResponse,(200..<300).contains(h.statusCode), let j = try JSONSerialization.jsonObject(with:d) as? [String:Any] else { continue }
                let title = sanitize((j["title"] as? String) ?? "youtube-\(id)")
                let thumb = (j["thumbnailUrl"] as? String).flatMap(URL.init(string:))
                let streams = (j["videoStreams"] as? [[String:Any]] ?? []).compactMap { f -> DownloadMedia? in
                    guard let s=f["url"] as? String, let u=URL(string:s) else { return nil }
                    let format = (f["format"] as? String ?? "").lowercased(); guard format.contains("mp4") || (f["mimeType"] as? String ?? "").contains("mp4") else { return nil }
                    let q = f["quality"] as? String ?? "فيديو"; let videoOnly = f["videoOnly"] as? Bool ?? false
                    return DownloadMedia(url:u, filename:"\(title)-\(q).mp4", type:"video", thumb:thumb, referer:"https://www.youtube.com/", platform:.youtube, quality:q, estimatedSize:(f["contentLength"] as? NSNumber)?.int64Value, hasAudio:!videoOnly)
                }
                let progressive = streams.filter{$0.hasAudio}.sorted{ qualityNumber($0.quality) > qualityNumber($1.quality) }
                if !progressive.isEmpty { return Array(progressive.prefix(4)) }
                if !streams.isEmpty { return Array(streams.sorted{qualityNumber($0.quality)>qualityNumber($1.quality)}.prefix(3)) }
            } catch { continue }
        }
        throw AppError.message("Piped unavailable")
    }

    private func youtubeInvidious(_ id:String) async throws -> [DownloadMedia] {
        let hosts = ["https://inv.nadeko.net","https://invidious.nerdvpn.de","https://yt.chocolatemoo53.com"]
        for host in hosts {
            guard let endpoint=URL(string:"\(host)/api/v1/videos/\(id)") else { continue }
            do {
                var r=URLRequest(url:endpoint); r.timeoutInterval=8; r.setValue(ua,forHTTPHeaderField:"User-Agent")
                let (d,res)=try await URLSession.shared.data(for:r); guard let h=res as? HTTPURLResponse,(200..<300).contains(h.statusCode), let j=try JSONSerialization.jsonObject(with:d) as? [String:Any] else { continue }
                let title=sanitize((j["title"] as? String) ?? "youtube-\(id)"); let thumb=(j["videoThumbnails"] as? [[String:Any]])?.compactMap{($0["url"] as? String).flatMap(URL.init(string:))}.first
                let fs=(j["formatStreams"] as? [[String:Any]] ?? []).compactMap { f -> DownloadMedia? in guard let s=f["url"] as? String,let u=URL(string:s) else{return nil}; let q=f["qualityLabel"] as? String ?? f["quality"] as? String ?? "فيديو"; return DownloadMedia(url:u,filename:"\(title)-\(q).mp4",type:"video",thumb:thumb,referer:"https://www.youtube.com/",platform:.youtube,quality:q,estimatedSize:(f["clen"] as? String).flatMap(Int64.init),hasAudio:true) }.sorted{qualityNumber($0.quality)>qualityNumber($1.quality)}
                if !fs.isEmpty { return Array(fs.prefix(4)) }
            } catch { continue }
        }
        throw AppError.message("Invidious unavailable")
    }

    private func youtubeWatch(_ id:String) async throws -> [DownloadMedia] {
        let watch=URL(string:"https://www.youtube.com/watch?v=\(id)&hl=en&gl=US&bpctr=9999999999")!; let (html,_)=try await fetchHTML(watch,referer:"https://www.youtube.com/")
        guard let text=extractJSONObject(after:"ytInitialPlayerResponse =",in:html),let d=text.data(using:.utf8),let j=try JSONSerialization.jsonObject(with:d) as? [String:Any],let stream=j["streamingData"] as? [String:Any] else{return []}
        let details=j["videoDetails"] as? [String:Any]; let title=sanitize((details?["title"] as? String) ?? "youtube-\(id)"); let thumb=((details?["thumbnail"] as? [String:Any])?["thumbnails"] as? [[String:Any]])?.compactMap{($0["url"] as? String).flatMap(URL.init(string:))}.last
        return (stream["formats"] as? [[String:Any]] ?? []).compactMap { f -> DownloadMedia? in guard let s=f["url"] as? String,let u=URL(string:s) else{return nil}; let q=f["qualityLabel"] as? String ?? "فيديو"; return DownloadMedia(url:u,filename:"\(title)-\(q).mp4",type:"video",thumb:thumb,referer:"https://www.youtube.com/",platform:.youtube,quality:q,estimatedSize:(f["contentLength"] as? String).flatMap(Int64.init),hasAudio:true) }.sorted{qualityNumber($0.quality)>qualityNumber($1.quality)}
    }

    func resolveX(_ source:URL) async throws -> [DownloadMedia] {
        guard let sid=source.pathComponents.first(where:{$0.count>8 && $0.allSatisfy(\.isNumber)}) else{throw AppError.message("رابط X غير معروف")}; let c=source.pathComponents; let user=c.count>1 ? c[1]:"i"; let endpoint=URL(string:"https://api.fxtwitter.com/\(user)/status/\(sid)")!; let (d,res)=try await URLSession.shared.data(from:endpoint); guard let h=res as? HTTPURLResponse,(200..<300).contains(h.statusCode),let j=try JSONSerialization.jsonObject(with:d) as? [String:Any] else{throw URLError(.badServerResponse)}; let tweet=(j["tweet"] as? [String:Any]) ?? j; var out:[DownloadMedia]=[]
        if let media=tweet["media"] as? [String:Any] {
            for (i,v) in (media["videos"] as? [[String:Any]] ?? []).enumerated() { let vars=(v["variants"] as? [[String:Any]] ?? []).compactMap{x -> (URL,Int)? in guard let s=x["url"] as? String,s.contains(".mp4"),let u=URL(string:s) else{return nil};return(u,x["bitrate"] as? Int ?? 0)}; if let best=vars.max(by:{$0.1<$1.1}) { out.append(DownloadMedia(url:best.0,filename:"x-\(sid)-\(i+1).mp4",type:"video",thumb:nil,referer:source.absoluteString,platform:.x,quality:"أعلى جودة")) } }
            for (i,p) in (media["photos"] as? [[String:Any]] ?? []).enumerated() { if let s=p["url"] as? String,let u=URL(string:s){out.append(DownloadMedia(url:u,filename:"x-\(sid)-\(i+1).jpg",type:"photo",thumb:u,referer:source.absoluteString,platform:.x,quality:"صورة"))} }
        }
        if out.isEmpty{throw AppError.message("لا توجد وسائط في المنشور")}; return out
    }

    func resolveMeta(_ source:URL,_ p:PlatformKind) async throws -> [DownloadMedia] {
        let (html,final)=try await fetchHTML(source,referer:source.absoluteString); if let s=meta(html,["og:video","og:video:url","twitter:player:stream"]).first,let u=URL(string:htmlDecode(s)){return[DownloadMedia(url:u,filename:"\(p.rawValue.lowercased())-video.mp4",type:"video",thumb:meta(html,["og:image"]).first.flatMap{URL(string:htmlDecode($0))},referer:final.absoluteString,platform:p)]}; let imgs=meta(html,["og:image","twitter:image"]).compactMap{URL(string:htmlDecode($0))}; if !imgs.isEmpty{return imgs.enumerated().map{i,u in DownloadMedia(url:u,filename:"\(p.rawValue.lowercased())-\(i+1).jpg",type:"photo",thumb:u,referer:final.absoluteString,platform:p,quality:"صورة")}}; throw AppError.message("تعذر قراءة المحتوى")
    }

    private func youtubeID(_ u:URL)->String? { if (u.host ?? "").contains("youtu.be"){return u.pathComponents.dropFirst().first}; if let c=URLComponents(url:u,resolvingAgainstBaseURL:false),let v=c.queryItems?.first(where:{$0.name=="v"})?.value,!v.isEmpty{return v}; let a=u.pathComponents; if let i=a.firstIndex(where:{$0=="shorts" || $0=="embed" || $0=="live"}),i+1<a.count{return a[i+1]}; return nil }
    private func qualityNumber(_ s:String)->Int { Int(s.filter(\.isNumber)) ?? 0 }
    private func fetchHTML(_ u:URL,referer:String?) async throws -> (String,URL) { var r=URLRequest(url:u);r.timeoutInterval=30;r.setValue(ua,forHTTPHeaderField:"User-Agent");if let referer{r.setValue(referer,forHTTPHeaderField:"Referer")};let(d,res)=try await URLSession.shared.data(for:r);guard let h=res as? HTTPURLResponse,(200..<400).contains(h.statusCode),let s=String(data:d,encoding:.utf8) else{throw URLError(.badServerResponse)};return(s,h.url ?? u) }
    private func regexFirst(_ s:String,_ p:String)->String? { guard let re=try? NSRegularExpression(pattern:p,options:[.dotMatchesLineSeparators,.caseInsensitive]),let m=re.firstMatch(in:s,range:NSRange(s.startIndex...,in:s)),m.numberOfRanges>1,let r=Range(m.range(at:1),in:s) else{return nil};return String(s[r]) }
    private func extractJSONObject(after marker:String,in text:String)->String? { guard let mr=text.range(of:marker) else{return nil};var i=mr.upperBound;while i<text.endIndex && text[i] != "{"{i=text.index(after:i)};guard i<text.endIndex else{return nil};var depth=0,inside=false,esc=false,j=i;while j<text.endIndex{let c=text[j];if inside{if esc{esc=false}else if c=="\\"{esc=true}else if c=="\""{inside=false}}else{if c=="\""{inside=true}else if c=="{"{depth+=1}else if c=="}"{depth-=1;if depth==0{return String(text[i...j])}}};j=text.index(after:j)};return nil }
    private func meta(_ html:String,_ names:[String])->[String] { var out:[String]=[];for n in names{let e=NSRegularExpression.escapedPattern(for:n);for p in [#"<meta[^>]+(?:property|name)=[\"']"#+e+#"[\"'][^>]+content=[\"']([^\"']+)[\"']"#,#"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']"#+e+#"[\"']"#]{if let x=regexFirst(html,p){out.append(x)}}};return out }
    private func firstURL(_ v:Any,keys:[String])->String? { if let d=v as? [String:Any]{for k in keys{if let s=d[k] as? String,s.hasPrefix("http"){return s};if let a=d[k] as? [String],let s=a.first(where:{$0.hasPrefix("http")}){return s};if let sub=d[k] as? [String:Any],let a=(sub["urlList"] ?? sub["url_list"]) as? [String],let s=a.first{return s}};for child in d.values{if let x=firstURL(child,keys:keys){return x}}};if let a=v as? [Any]{for child in a{if let x=firstURL(child,keys:keys){return x}}};return nil }
    private func firstString(_ v:Any,keys:[String])->String? { if let d=v as? [String:Any]{for k in keys{if let s=d[k] as? String,!s.isEmpty{return s};if let n=d[k] as? NSNumber{return n.stringValue}};for child in d.values{if let x=firstString(child,keys:keys){return x}}};if let a=v as? [Any]{for child in a{if let x=firstString(child,keys:keys){return x}}};return nil }
    private func tikTokImages(_ value:Any)->[URL] { var f:[URL]=[];func walk(_ v:Any){if let d=v as? [String:Any]{if let ip=d["imagePost"] as? [String:Any],let imgs=ip["images"] as? [[String:Any]]{for x in imgs{if let s=firstURL(x,keys:["displayImage","imageURL","imageUrl","ownerWatermarkImage"]),let u=URL(string:s){f.append(u)}}};for child in d.values{walk(child)}}else if let a=v as? [Any]{a.forEach(walk)}};walk(value);var seen=Set<String>();return f.filter{seen.insert($0.absoluteString).inserted} }
    private func decodeEscapedURL(_ s:String)->String { s.replacingOccurrences(of:"\\u002F",with:"/").replacingOccurrences(of:"\\/",with:"/").replacingOccurrences(of:"\\u0026",with:"&") }
    private func htmlDecode(_ s:String)->String { s.replacingOccurrences(of:"&amp;",with:"&").replacingOccurrences(of:"&#x2F;",with:"/") }
}
