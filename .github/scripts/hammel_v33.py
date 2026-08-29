from pathlib import Path
import re

root = Path('V11')

# Existing source syntax/runtime fixes.
p = root / 'FullMediaSuite.swift'
s = p.read_text()
s = s.replace('])}private func run(', '])}; private func run(')
s = s.replace('])}private func crop(', '])}; private func crop(')
s = s.replace('}}private func format(', '}}; private func format(')
s = s.replace('.presentationDetents([.medium])', '.presentationDetents([.large])')
p.write_text(s)

p = root / 'SmartFeaturesCore.swift'
s = p.read_text()
if 'import AVFoundation' not in s:
    s = s.replace('import Foundation\n', 'import Foundation\nimport AVFoundation\n', 1)
p.write_text(s)

p = root / 'SmartFeaturesUI.swift'
s = p.read_text()
s = s.replace('if m.hasAudio{Image(systemName:"speaker.wave.2.fill").foregroundStyle(.green)}}}.padding', 'if m.hasAudio{Image(systemName:"speaker.wave.2.fill").foregroundStyle(.green)}}}}.padding')
p.write_text(s)

p = root / 'SmartVideoTools.swift'
s = p.read_text()
for old,new in [
    ('outputFileType=.mp4','outputFileType = .mp4'),
    ('outputFileType=.m4a','outputFileType = .m4a'),
    ('taskHint=.dictation','taskHint = .dictation'),
    ('performSeparation(mode:.full)','performSeparation(mode: .full)'),
    ('outputFileType=.mov','outputFileType = .mov')
]:
    s = s.replace(old,new)
old = 'for seg in result.bestTranscription.segments{words.append(seg);if words.count>=9 || ((words.last?.timestamp ?? 0)+(words.last?.duration ?? 0)-(words.first?.timestamp ?? 0)>3.8){let s=start+(words.first?.timestamp ?? 0);let e=start+(words.last.map{$0.timestamp+$0.duration} ?? 0);let text=words.map(\\.substring).joined(separator:" ");let tr=try await translateV3(text,target:target);output.append(CaptionV3(start:s,end:max(s+0.2,e),source:text,translated:tr));words=[]}}'
new = '''for seg in result.bestTranscription.segments {
                    words.append(seg)
                    let firstTime = words.first?.timestamp ?? 0
                    let lastTime = (words.last?.timestamp ?? 0) + (words.last?.duration ?? 0)
                    let span = lastTime - firstTime
                    if words.count >= 9 || span > 3.8 {
                        let absoluteStart = start + firstTime
                        let absoluteEnd = start + lastTime
                        let text = words.map(\\.substring).joined(separator: " ")
                        let translated = try await translateV3(text, target: target)
                        output.append(CaptionV3(start: absoluteStart, end: max(absoluteStart + 0.2, absoluteEnd), source: text, translated: translated))
                        words.removeAll(keepingCapacity: true)
                    }
                }'''
if old in s:
    s = s.replace(old,new,1)
p.write_text(s)

# Route older entries to the fixed translation and Demucs implementations.
for p in root.glob('*.swift'):
    if p.name in ('DemucsVendor.swift','V26Fixes.swift','SmartFeaturesCore.swift','SmartVideoTools.swift','SmartFeaturesUI.swift'):
        continue
    s = p.read_text()
    s = s.replace('model.translateVideoToSRTComplete(', 'model.translateVideoToSRTV26(')
    s = s.replace('model.translateVideoToSRTFixed(', 'model.translateVideoToSRTV26(')
    s = s.replace('model.translateVideoToSRT(', 'model.translateVideoToSRTV26(')
    s = s.replace('TranslationChoiceSheet(', 'TranslationChoiceSheetV26(')
    s = s.replace('model.separateCenterAudioFast(', 'model.separateWithDemucs(')
    s = s.replace('model.separateCenterAudioFixed(', 'model.separateWithDemucs(')
    s = s.replace('model.separateCenterAudio(', 'model.separateWithDemucs(')
    p.write_text(s)

# App setup / main UI wiring.
p = root / 'AppCore.swift'
s = p.read_text()
if 'await applyDownloadRulesIfNeededV3(source: source)' not in s:
    s = s.replace('            results = media\n', '            results = media\n            await applyDownloadRulesIfNeededV3(source: source)\n', 1)
p.write_text(s)

p = root / 'Views.swift'
s = p.read_text()
s = s.replace('LibraryView(model:model).tabItem', 'LibraryViewV26(model:model).tabItem')
if 'safeAreaInset(edge:.bottom,spacing:0){FloatingPlaybackDock()}' not in s:
    s = s.replace('}.tint(T.olive).overlay(alignment:.top)', '}.tint(T.olive).safeAreaInset(edge:.bottom,spacing:0){FloatingPlaybackDock()}.overlay(alignment:.top)')
s = s.replace('Text("نزّل. رتّب. استخدم.").font(.caption).foregroundStyle(.secondary)', 'EmptyView()')
if 'QualityComparisonV3(model:model,items:model.results)' not in s:
    s = s.replace('        TextField("اسم الملف",text:$name)', '        if model.results.count > 1 { QualityComparisonV3(model:model,items:model.results) }\n        TextField("اسم الملف",text:$name)', 1)
if 'SmartAutomationHubV3(model:model)' not in s:
    s = s.replace('Section("المساحة"){', 'Section("ميزات متقدمة"){NavigationLink{SmartAutomationHubV3(model:model)}label:{Label("الأتمتة والذكاء",systemImage:"sparkles")}};Section("المساحة"){', 1)
p.write_text(s)

p = root / 'MediaViews.swift'
s = p.read_text()
s = s.replace('            }.padding(20)\n        }\n        .navigationTitle("تعديل الفيديو")', '            }.padding(20).padding(.bottom, 120)\n        }\n        .scrollIndicators(.visible)\n        .navigationTitle("تعديل الفيديو")', 1)
p.write_text(s)

# Library actions and CRITICAL PhotosPicker fix.
p = root / 'V26Fixes.swift'
s = p.read_text()
s = s.replace('.sheet(item: $actionItem) { MediaQuickActionsSheet(model: model, item: $0) }', '.sheet(item: $actionItem) { UnifiedFileActionsSheet(model: model, item: $0) }')
s = s.replace('.sheet(item: $actionItem) { MediaQuickActionsSheet(model: model, item: $0).presentationDetents([.large]) }', '.sheet(item: $actionItem) { UnifiedFileActionsSheet(model: model, item: $0) }')
pattern = r'if !selecting \{\s*Button \{ actionItem = item \} label: \{\s*Image\(systemName: "ellipsis"\)\.frame\(width: 34, height: 34\)\s*\}\.buttonStyle\(\.plain\)\s*\}'
repl = '''if !selecting {
                Button { actionItem = item } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(olive)
                        .frame(width: 34, height: 34)
                        .background(olive.opacity(0.10), in: Circle())
                }.buttonStyle(.plain)
                Button { actionItem = item } label: {
                    Image(systemName: "ellipsis").frame(width: 34, height: 34)
                }.buttonStyle(.plain)
            }'''
s = re.sub(pattern, repl, s, count=1, flags=re.S)
old_picker = '''            .onChange(of: picker) { _, new in
                Task {
                    for p in new {
                        if let data = try? await p.loadTransferable(type: Data.self) { model.importImageData(data, ext: "jpg") }
                    }
                    picker = []
                }
            }'''
new_picker = '''            .onChange(of: picker) { _, new in
                Task {
                    for picked in new {
                        let types = picked.supportedContentTypes
                        let chosenType = types.first(where: { $0.conforms(to: .movie) })
                            ?? types.first(where: { $0.conforms(to: .image) })
                            ?? types.first
                        let ext: String
                        if let chosenType, chosenType.conforms(to: .movie) {
                            ext = chosenType.preferredFilenameExtension ?? "mov"
                        } else if let chosenType {
                            ext = chosenType.preferredFilenameExtension ?? "jpg"
                        } else {
                            ext = "jpg"
                        }
                        if let data = try? await picked.loadTransferable(type: Data.self) {
                            model.importImageData(data, ext: ext)
                        }
                    }
                    picker = []
                }
            }'''
if old_picker not in s:
    raise SystemExit('PhotosPicker block not found')
s = s.replace(old_picker,new_picker,1)
p.write_text(s)

# Download reliability and HQ mux fallback.
p = root / 'SmartDownload.swift'
s = p.read_text()
s = s.replace('if (url.host ?? "").contains("googlevideo.com"), let accelerated = try? await parallelSmallDownload(url, referer: referer, progress: progress) {', 'if false, let accelerated = try? await parallelSmallDownload(url, referer: referer, progress: progress) {')
old_download = 'return try await BackgroundDownloadBroker.shared.download(req, progress: progress)'
new_download = '''do {
            let (tmp, response) = try await URLSession.shared.download(for: req)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            progress(1)
            return tmp
        } catch {
            return try await BackgroundDownloadBroker.shared.download(req, progress: progress)
        }'''
if old_download not in s:
    raise SystemExit('smartDownload path not found')
s = s.replace(old_download,new_download,1)
s = s.replace('try await mux(video: videoTmp, audio: audioTmp, output: mergedTmp)', 'do { try await muxHQReliableV32(video: videoTmp, audio: audioTmp, output: mergedTmp) } catch { try await mux(video: videoTmp, audio: audioTmp, output: mergedTmp) }')
p.write_text(s)

# Build-time regression checks.
v26 = (root / 'V26Fixes.swift').read_text()
down = (root / 'SmartDownload.swift').read_text()
smart = (root / 'UnifiedFileActions.swift').read_text()
tools = (root / 'SmartVideoTools.swift').read_text()
assert 'chosenType.conforms(to: .movie)' in v26
assert 'URLSession.shared.download(for: req)' in down
assert 'BackgroundDownloadBroker.shared.download' in down
assert 'muxHQReliableV32' in down and 'try await mux(video:' in down
for label in ['Smart Clip','ترجمة عربية','حذف الصمت','تتبع 9:16','تنظيف الصوت','صور غلاف']:
    assert label in smart
assert 'let firstTime = words.first?.timestamp ?? 0' in tools
