import XCTest
import UIKit
import SwiftUI
import PDFKit
import AVFAudio
import NinhoCore
@testable import Ninho

/// These tests require Xcode/iOS. Linux checks do not execute this target.
@MainActor final class AppleIntegrationTests: XCTestCase {
    func testBundledCatalogueDecodesWithoutInventedHistory() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "seed-state", withExtension: "json"))
        let state = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
        try StudyEngine.validate(state)
        XCTAssertFalse(state.programs.isEmpty)
        XCTAssertFalse(state.lessons.isEmpty)
        XCTAssertTrue(state.sessions.isEmpty)
        XCTAssertTrue(state.cards.allSatisfy { $0.repetitions == 0 })
        XCTAssertNotNil(UIImage(named: "owl"))
    }

    func testImportedPDFReopensInRealPDFKitAndAppReader() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ninho-AppleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sintetico.pdf")
        let page = CGRect(x: 0, y: 0, width: 320, height: 480)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { renderer in
            for index in 1...2 {
                renderer.beginPage()
                UIColor.white.setFill(); renderer.cgContext.fill(page)
                UIColor.systemGreen.setFill(); renderer.cgContext.fill(CGRect(x: 20, y: 20, width: 100, height: 120))
                ("Ninho PDF sintético \(index)" as NSString).draw(at: CGPoint(x: 20, y: 180), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.black])
            }
        }
        try data.write(to: source)
        let library = StudyLibrary(root: root.appendingPathComponent("library"))
        _ = try await library.load()
        let imported = try await library.importMaterial(from: source)
        let material = try XCTUnwrap(imported.materials.first)
        let url = try await library.materialURL(id: material.id)
        XCTAssertEqual(try Data(contentsOf: url), data)
        let host = UIHostingController(rootView: PDFReader(url: url))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        for _ in 0..<100 {
            if descendant(PDFView.self, in: host.view) != nil { break }
            try await Task.sleep(for: .milliseconds(10)); host.view.layoutIfNeeded()
        }
        let pdfView = try XCTUnwrap(descendant(PDFView.self, in: host.view))
        XCTAssertEqual(pdfView.document?.pageCount, 2)
        XCTAssertTrue(pdfView.document?.page(at: 0)?.string?.contains("Ninho PDF") == true)
        XCTAssertEqual(pdfView.accessibilityIdentifier, "material.pdf")
        let raster = try XCTUnwrap(pdfView.document?.page(at: 0)?.thumbnail(of: CGSize(width: 320, height: 480), for: .mediaBox).cgImage)
        XCTAssertGreaterThan(raster.width, 100)
        XCTAssertGreaterThan(raster.height, 100)
        assertGreenPagePixels(raster)
    }

    func testSeveralMegabytePDFRendersRealColoredPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ninho-AppleLargePDF-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.main.url(forResource: "test-material-large", withExtension: "pdf"))
        XCTAssertGreaterThan(try Data(contentsOf: source).count, 3 * 1024 * 1024)
        let library = StudyLibrary(root: root)
        let imported = try await library.importMaterial(from: source)
        let url = try await library.materialURL(id: XCTUnwrap(imported.materials.first).id)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertTrue(page.string?.contains("Ninho PDF sintetico") == true)
        let raster = try XCTUnwrap(page.thumbnail(of: CGSize(width: 320, height: 480), for: .mediaBox).cgImage)
        assertGreenPagePixels(raster)
    }

    func testUnreadablePDFShowsAppErrorInsteadOfBlankReader() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("Ninho-missing-\(UUID().uuidString).pdf")
        let host = UIHostingController(rootView: PDFReader(url: missing))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        for _ in 0..<100 {
            if descendant(UILabel.self, in: host.view) != nil { break }
            try await Task.sleep(for: .milliseconds(10)); host.view.layoutIfNeeded()
        }
        XCTAssertNil(descendant(PDFView.self, in: host.view))
        let label = try XCTUnwrap(descendant(UILabel.self, in: host.view))
        XCTAssertEqual(label.accessibilityIdentifier, "material.pdfError")
        XCTAssertTrue(label.text?.contains("Não foi possível") == true)
    }

    func testOriginalSoundCuesDecodeWithNativeAudioWithoutPlayback() throws {
        for cue in SoundCue.allCases {
            let player = try AVAudioPlayer(data: StudySounds.waveData(for: cue))
            XCTAssertEqual(player.numberOfChannels, 1)
            XCTAssertEqual(player.duration, StudySounds.duration(for: cue), accuracy: 0.002)
            XCTAssertFalse(player.isPlaying)
        }
    }

    func testUnavailableAssistantPublishesHonestStateAndNoGeneratedReply() {
        let model = LocalAssistantModel(client: UnavailableAssistantClient(reason: .modelNotReady))
        model.refreshAvailability()
        XCTAssertEqual(model.availability, .unavailable(.modelNotReady))
        XCTAssertFalse(model.send("O que revisar?", state: AppState()))
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertFalse(model.isResponding)
        model.newConversation(); model.deactivate()
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(model.availability, .unavailable(.modelNotReady))
    }

    private func descendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews { if let match = descendant(type, in: child) { return match } }
        return nil
    }

    private func assertGreenPagePixels(_ image: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            context.setFillColor(UIColor.white.cgColor); context.fill(bounds)
            context.draw(image, in: bounds)
            return true
        }
        XCTAssertTrue(drawn, file: file, line: line)
        let green = stride(from: 0, to: bytes.count, by: 4).filter { offset in
            let red = Int(bytes[offset]), value = Int(bytes[offset + 1]), blue = Int(bytes[offset + 2])
            return value > 70 && value > red + 20 && value > blue + 20
        }.count
        XCTAssertGreaterThan(Double(green) / Double(width * height), 0.04, "The actual PDF page must contain its green rectangle, not a white/blank raster.", file: file, line: line)
    }
}
