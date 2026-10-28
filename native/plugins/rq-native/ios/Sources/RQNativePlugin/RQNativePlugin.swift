import Foundation
import UIKit
import CoreLocation
import Capacitor
import PassKit
import Network

/// Background driver location (posted straight to Supabase so it keeps working
/// while the web view is suspended) and screen keep-awake.
@objc(RQNativePlugin)
public class RQNativePlugin: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate, PKPaymentAuthorizationControllerDelegate {
    public let identifier = "RQNativePlugin"
    public let jsName = "RQNative"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startTracking", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopTracking", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "keepAwake", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "applePayAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "applePay", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "applePayComplete", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "tcpSend", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "tcpProbe", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "localIp", returnType: CAPPluginReturnPromise)
    ]

    private var manager: CLLocationManager?
    private var endpoint: URL?
    private var apiKey = ""
    private var token = ""
    private var lastSent = Date.distantPast
    private var lastLoc: CLLocation?
    private var tracking = false
    private var lastOk: Date?

    @objc func startTracking(_ call: CAPPluginCall) {
        guard let url = call.getString("url"), let key = call.getString("key"), let tok = call.getString("token"),
              let ep = URL(string: url + "/rest/v1/rpc/app_driver_location") else {
            call.reject("missing url/key/token"); return
        }
        endpoint = ep; apiKey = key; token = tok
        DispatchQueue.main.async {
            if self.manager == nil {
                let m = CLLocationManager()
                m.delegate = self
                m.desiredAccuracy = kCLLocationAccuracyBest
                m.distanceFilter = 15
                m.activityType = .automotiveNavigation
                m.pausesLocationUpdatesAutomatically = false
                self.manager = m
            }
            guard let m = self.manager else { return }
            let st = m.authorizationStatus
            if st == .notDetermined { m.requestWhenInUseAuthorization() }
            else if st == .authorizedWhenInUse { m.requestAlwaysAuthorization() }
            self.enableBackground(m)
            m.startUpdatingLocation()
            self.tracking = true
            call.resolve(["ok": true, "auth": self.authName(m.authorizationStatus)])
        }
    }

    @objc func stopTracking(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.manager?.stopUpdatingLocation()
            self.manager?.allowsBackgroundLocationUpdates = false
            self.tracking = false
            call.resolve(["ok": true])
        }
    }

    @objc func keepAwake(_ call: CAPPluginCall) {
        let on = call.getBool("on") ?? true
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = on
            call.resolve(["ok": true])
        }
    }

    @objc func status(_ call: CAPPluginCall) {
        let st = manager?.authorizationStatus ?? CLLocationManager().authorizationStatus
        var r: [String: Any] = ["tracking": tracking, "auth": authName(st)]
        if let d = lastOk { r["lastSent"] = d.timeIntervalSince1970 * 1000 }
        call.resolve(r)
    }

    private func enableBackground(_ m: CLLocationManager) {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modes.contains("location") {
            m.allowsBackgroundLocationUpdates = true
            m.showsBackgroundLocationIndicator = true
        }
    }

    private func authName(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        case .denied: return "denied"
        case .restricted: return "restricted"
        default: return "notDetermined"
        }
    }

    public func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse && tracking { m.requestAlwaysAuthorization() }
        if tracking { enableBackground(m); m.startUpdatingLocation() }
        notifyListeners("auth", data: ["auth": authName(m.authorizationStatus)])
    }

    public func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 else { return }
        let moved = lastLoc.map { loc.distance(from: $0) > 30 } ?? true
        let gap = Date().timeIntervalSince(lastSent)
        if gap < (moved ? 8 : 25) { return }
        lastSent = Date(); lastLoc = loc
        send(loc)
    }

    private func send(_ loc: CLLocation) {
        guard let ep = endpoint, !token.isEmpty else { return }
        var req = URLRequest(url: ep)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["t": token, "lat": loc.coordinate.latitude, "lng": loc.coordinate.longitude]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var bg: UIBackgroundTaskIdentifier = .invalid
        bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg); bg = .invalid }
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let h = resp as? HTTPURLResponse, h.statusCode < 300 {
                self.lastOk = Date()
                if let d = data, let s = String(data: d, encoding: .utf8), s.contains("\"auth\"") {
                    // token no longer valid: stop sending
                    DispatchQueue.main.async { self.manager?.stopUpdatingLocation(); self.tracking = false }
                }
            }
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
        }.resume()
    }

    // MARK: Apple Pay — the sheet returns an encrypted payment token that the page sends
    // to the server, which charges it through the payment gateway; the page then calls
    // applePayComplete so the sheet shows success or failure.
    private let payNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .mada]
    private var payCall: CAPPluginCall?
    private var payDone: ((PKPaymentAuthorizationResult) -> Void)?
    private var payController: PKPaymentAuthorizationController?
    private var payAuthorized = false

    private func merchantIds() -> [String] {
        let ent = Bundle.main.object(forInfoDictionaryKey: "RQMerchantIds") as? [String]
        return ent ?? []
    }

    @objc func applePayAvailable(_ call: CAPPluginCall) {
        let mid = call.getString("merchantId") ?? ""
        let configured = merchantIds().contains(mid)
        call.resolve(["available": configured && PKPaymentAuthorizationController.canMakePayments(),
                      "cards": PKPaymentAuthorizationController.canMakePayments(usingNetworks: payNetworks),
                      "configured": configured])
    }

    @objc func applePay(_ call: CAPPluginCall) {
        guard let mid = call.getString("merchantId"), let items = call.getArray("items", JSObject.self), !items.isEmpty else {
            call.reject("missing merchantId/items"); return
        }
        let req = PKPaymentRequest()
        req.merchantIdentifier = mid
        req.countryCode = call.getString("country") ?? "AE"
        req.currencyCode = call.getString("currency") ?? "AED"
        req.supportedNetworks = payNetworks
        req.merchantCapabilities = [.threeDSecure]
        req.paymentSummaryItems = items.map { it in
            var amt = "0"
            if let s = it["amount"] as? String { amt = s }
            else if let n = it["amount"] as? NSNumber { amt = n.stringValue }
            else if let d = it["amount"] as? Double { amt = String(format: "%.2f", d) }
            return PKPaymentSummaryItem(label: (it["label"] as? String) ?? "", amount: NSDecimalNumber(string: amt))
        }
        payCall = call; payAuthorized = false
        DispatchQueue.main.async {
            let c = PKPaymentAuthorizationController(paymentRequest: req)
            c.delegate = self
            self.payController = c
            c.present { shown in if !shown { self.payCall?.reject("could not show Apple Pay"); self.payCall = nil } }
        }
    }

    @objc func applePayComplete(_ call: CAPPluginCall) {
        let ok = call.getBool("ok") ?? false
        DispatchQueue.main.async {
            self.payDone?(PKPaymentAuthorizationResult(status: ok ? .success : .failure, errors: nil))
            self.payDone = nil
            call.resolve(["ok": true])
        }
    }

    public func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        payAuthorized = true
        payDone = completion
        let t = payment.token
        payCall?.resolve(["token": t.paymentData.base64EncodedString(),
                          "network": t.paymentMethod.network?.rawValue ?? "",
                          "display": t.paymentMethod.displayName ?? "",
                          "transactionId": t.transactionIdentifier])
        payCall = nil
        // safety: never leave the sheet spinning if the page never answers
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            if let d = self.payDone { d(PKPaymentAuthorizationResult(status: .failure, errors: nil)); self.payDone = nil }
        }
    }

    public func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {}
        if !payAuthorized { payCall?.reject("cancelled"); payCall = nil }
        payController = nil
    }

    // MARK: Network receipt printers (Epson TM etc.) — raw ESC/POS over TCP port 9100.
    private let netQueue = DispatchQueue(label: "rq.net", attributes: .concurrent)

    @objc func tcpSend(_ call: CAPPluginCall) {
        guard let host = call.getString("host"), let b64 = call.getString("data"), let data = Data(base64Encoded: b64) else {
            call.reject("missing host/data"); return
        }
        let port = NWEndpoint.Port(rawValue: UInt16(call.getInt("port") ?? 9100)) ?? 9100
        let timeout = Double(call.getInt("timeout") ?? 8000) / 1000.0
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        var finished = false
        let lock = NSLock()
        func finish(_ err: String?) {
            lock.lock(); defer { lock.unlock() }
            if finished { return }
            finished = true
            conn.cancel()
            if let e = err { call.reject(e) } else { call.resolve(["ok": true]) }
        }
        conn.stateUpdateHandler = { st in
            switch st {
            case .ready:
                conn.send(content: data, completion: .contentProcessed { err in
                    if let e = err { finish("send: \(e)"); return }
                    // give the printer a moment to take the buffer before closing
                    self.netQueue.asyncAfter(deadline: .now() + 0.3) { finish(nil) }
                })
            case .failed(let e): finish("connect: \(e)")
            case .waiting(let e): finish("unreachable: \(e)")
            default: break
            }
        }
        conn.start(queue: netQueue)
        netQueue.asyncAfter(deadline: .now() + timeout + 2) { finish("timeout") }
    }

    @objc func tcpProbe(_ call: CAPPluginCall) {
        guard let host = call.getString("host") else { call.reject("missing host"); return }
        let port = NWEndpoint.Port(rawValue: UInt16(call.getInt("port") ?? 9100)) ?? 9100
        let timeout = Double(call.getInt("timeout") ?? 600) / 1000.0
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        var done = false
        let lock = NSLock()
        func finish(_ open: Bool) {
            lock.lock(); defer { lock.unlock() }
            if done { return }
            done = true
            conn.cancel()
            call.resolve(["open": open, "host": host])
        }
        conn.stateUpdateHandler = { st in
            switch st {
            case .ready: finish(true)
            case .failed, .waiting: finish(false)
            default: break
            }
        }
        conn.start(queue: netQueue)
        netQueue.asyncAfter(deadline: .now() + timeout) { finish(false) }
    }

    @objc func localIp(_ call: CAPPluginCall) {
        var ip: String? = nil
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let first = ifaddr {
            var p: UnsafeMutablePointer<ifaddrs>? = first
            while let cur = p {
                let ifa = cur.pointee
                if ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    let name = String(cString: ifa.ifa_name)
                    if name == "en0" || (ip == nil && name.hasPrefix("en")) {
                        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                        ip = String(cString: host)
                    }
                }
                p = ifa.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        call.resolve(["ip": ip ?? ""])
    }

}
