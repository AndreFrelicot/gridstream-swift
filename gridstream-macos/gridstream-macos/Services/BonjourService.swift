import Foundation
import OSLog

final class BonjourService: NSObject, NetServiceDelegate {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "BonjourService")
    private var netService: NetService?
    private(set) var isPublished = false

    func publish(port: Int) {
        stop()

        let service = NetService(
            domain: "",
            type: "_gridstream._tcp.",
            name: "GridStream",
            port: Int32(port)
        )

        service.delegate = self
        service.publish()

        netService = service
        logger.info("Publishing Bonjour service on port \(port)")
    }

    func stop() {
        guard let service = netService else { return }

        service.stop()
        netService = nil
        isPublished = false
        logger.info("Stopped Bonjour service")
    }

    func netServiceDidPublish(_ sender: NetService) {
        isPublished = true
        logger.info("Bonjour service published successfully: \(sender.name)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        isPublished = false
        let errorCode = errorDict[NetService.errorCode] ?? -1
        let errorDomain = errorDict[NetService.errorDomain] ?? -1
        logger.error("Failed to publish Bonjour service - code: \(errorCode), domain: \(errorDomain)")
    }

    func netServiceDidStop(_ sender: NetService) {
        isPublished = false
        logger.info("Bonjour service stopped")
    }

    isolated deinit {
        stop()
    }
}
