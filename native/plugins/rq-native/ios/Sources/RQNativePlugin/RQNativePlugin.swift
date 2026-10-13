import Foundation
import UIKit
import CoreLocation
import Capacitor
import PassKit

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
        CAPPluginMethod(name: "applePayComplete", returnType: CAPPluginReturnPromise)
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

}
