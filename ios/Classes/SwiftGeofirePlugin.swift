import Flutter
import UIKit
import GeoFire
import FirebaseDatabase


public class SwiftGeofirePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let pendingWritesKey = "flutter_geofire_pending_writes"
    static var persistenceConfigured = false

    
    var geoFireRef:DatabaseReference?
    var geoFire:GeoFire?
    private var eventSink: FlutterEventSink?
    var circleQuery : GFCircleQuery?

    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "geofire", binaryMessenger: registrar.messenger())
    let instance = SwiftGeofirePlugin()

    let eventChannel = FlutterEventChannel(name: "geofireStream",
                                                  binaryMessenger: registrar.messenger())
    
    
    
    
    eventChannel.setStreamHandler(instance)
    
    registrar.addMethodCallDelegate(instance, channel: channel)
    
    
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    
    var key = [String]()
    
    let arguements = call.arguments as? NSDictionary
    
    if(call.method.elementsEqual("GeoFire.start")){

        configurePersistenceIfNeeded()
     
        let path = arguements!["path"] as! String
        
        geoFireRef = Database.database().reference().child(path)
        geoFire = GeoFire(firebaseRef: geoFireRef!)
        flushPendingWrites()
        
        result(true)
    }
    
    else if(call.method.elementsEqual("setLocation")){
        
        let id = arguements!["id"] as! String
        let lat = arguements!["lat"] as! Double
        let lng = arguements!["lng"] as! Double

        let request = createWriteRequest(id: id, lat: lat, lng: lng, data: [:])
        enqueuePendingWrite(request)

        writeLocationWithData(request) { isSuccess in
            if isSuccess {
                self.dequeuePendingWrite(request["requestId"] as! String)
                result(true)
            } else {
                result(false)
            }
        }
    
    }

    else if(call.method.elementsEqual("setLocationWithData") || call.method.elementsEqual("setLocationWithMetadata")){
        let id = arguements!["id"] as! String
        let lat = arguements!["lat"] as! Double
        let lng = arguements!["lng"] as! Double
        let data = arguements!["data"] as? [String: Any] ?? [:]
        let sanitized = self.sanitizeAdditionalData(data)
        let request = createWriteRequest(id: id, lat: lat, lng: lng, data: sanitized)

        enqueuePendingWrite(request)

        writeLocationWithData(request) { isSuccess in
            if isSuccess {
                self.dequeuePendingWrite(request["requestId"] as! String)
                result(true)
            } else {
                result(false)
            }
        }
    }
    
    else if(call.method.elementsEqual("removeLocation")){
        
        let id = arguements!["id"] as! String
        

        geoFire?.removeKey(id) { (error) in
            if (error != nil) {
                print("An error occured: \(String(describing: error))")
                result("An error occured: \(String(describing: error))")
                
            } else {
                print("Removed location successfully!")
                result(true)
            }
        }
        
    }
    else if(call.method.elementsEqual("stopListener")){
        
        circleQuery?.removeAllObservers()
        
        result(true);
        
    }
    
    else if(call.method.elementsEqual("getLocation")){
        
        let id = arguements!["id"] as! String
        
        
        geoFire?.getLocationForKey(id) { (location, error) in
            if (error != nil) {
                print("An error occurred getting the location for \(id): \(String(describing: error?.localizedDescription))")
            } else if (location != nil) {
                print("Location for \(id) is [\(String(describing: location?.coordinate.latitude)), \(location?.coordinate.longitude)]")
                
                var param=[String:AnyObject]()
                param["lat"]=location?.coordinate.latitude as AnyObject
                param["lng"]=location?.coordinate.longitude as AnyObject
                
                result(param)
                
            } else {
                
                var param=[String:AnyObject]()
                param["error"] = "GeoFire does not contain a location for \(id)" as AnyObject
            
                
                result(param)
                
                print("GeoFire does not contain a location for \"firebase-hq\"")
            }
        }
        
        
    }
    
    
    if(call.method.elementsEqual("queryAtLocation")){
        
        
        let lat = arguements!["lat"] as! Double
        let lng = arguements!["lng"] as! Double
        let radius = arguements!["radius"] as! Double
        let includeData = arguements?["includeData"] as? Bool ?? false
        
        
        let location:CLLocation = CLLocation(latitude: CLLocationDegrees(lat), longitude: CLLocationDegrees(lng))
        
        circleQuery = geoFire?.query(at: location, withRadius: radius)
        
        _ = circleQuery?.observe(.keyEntered, with: { (parkingKey, location) in
            key.append(parkingKey)
            print("Key is \(parkingKey)")
            self.emitQueryEventWithData(callBack: "onKeyEntered", key: parkingKey, location: location, includeData: includeData)
            
        })
        
        _ = circleQuery?.observe(.keyMoved, with: { (parkingKey, location) in
            key.append(parkingKey)
            print("Key is \(parkingKey)")
            self.emitQueryEventWithData(callBack: "onKeyMoved", key: parkingKey, location: location, includeData: includeData)
            
        })
        
        _ = circleQuery?.observe(.keyExited, with: { (parkingKey, location) in
            self.emitQueryEventWithData(callBack: "onKeyExited", key: parkingKey, location: location, includeData: includeData)
            
        })
        
        
        circleQuery?.observeReady {
            
            var param=[String:Any]()
            
            param["callBack"] = "onGeoQueryReady"
            param["result"] = key
            self.eventSink!(param)
            
        }
    }
    
  }


   public func onListen(withArguments arguments: Any?,
                       eventSink: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = eventSink
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
      eventSink = nil
      return nil
    }




    private func sanitizeAdditionalData(_ metadata: [String: Any]) -> [AnyHashable: Any] {
        var sanitized: [AnyHashable: Any] = [:]

        for (key, value) in metadata {
            if key == "g" || key == "l" {
                continue
            }
            sanitized[key] = value
        }

        return sanitized
    }

    private func configurePersistenceIfNeeded() {
        if SwiftGeofirePlugin.persistenceConfigured {
            return
        }

        Database.database().isPersistenceEnabled = true
        SwiftGeofirePlugin.persistenceConfigured = true
    }

    private func loadPendingWrites() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: SwiftGeofirePlugin.pendingWritesKey) as? [[String: Any]] ?? []
    }

    private func savePendingWrites(_ writes: [[String: Any]]) {
        UserDefaults.standard.set(writes, forKey: SwiftGeofirePlugin.pendingWritesKey)
    }

    private func enqueuePendingWrite(_ request: [String: Any]) {
        var writes = loadPendingWrites()
        writes.append(request)
        savePendingWrites(writes)
    }

    private func dequeuePendingWrite(_ requestId: String) {
        let filtered = loadPendingWrites().filter { request in
            (request["requestId"] as? String) != requestId
        }
        savePendingWrites(filtered)
    }

    private func flushPendingWrites() {
        let writes = loadPendingWrites()
        for request in writes {
            writeLocationWithData(request) { isSuccess in
                if isSuccess, let requestId = request["requestId"] as? String {
                    self.dequeuePendingWrite(requestId)
                }
            }
        }
    }

    private func writeLocationWithData(_ request: [String: Any], completion: @escaping (Bool) -> Void) {
        guard
            let geoFire = geoFire,
            let ref = geoFireRef,
            let id = request["id"] as? String,
            let lat = request["lat"] as? Double,
            let lng = request["lng"] as? Double
        else {
            completion(false)
            return
        }

        let data = request["data"] as? [AnyHashable: Any] ?? [:]

        geoFire.setLocation(CLLocation(latitude: lat, longitude: lng), forKey: id) { error in
            if error != nil {
                completion(false)
                return
            }

            if data.isEmpty {
                completion(true)
                return
            }

            let payload: [AnyHashable: Any] = ["data": data]
            ref.child(id).updateChildValues(payload) { metadataError, _ in
                completion(metadataError == nil)
            }
        }
    }

    private func createWriteRequest(id: String, lat: Double, lng: Double, data: [AnyHashable: Any]) -> [String: Any] {
        return [
            "requestId": UUID().uuidString,
            "id": id,
            "lat": lat,
            "lng": lng,
            "data": data
        ]
    }

    private func emitQueryEventWithData(callBack: String, key: String, location: CLLocation, includeData: Bool) {
        guard let sink = eventSink else {
            circleQuery?.removeAllObservers()
            return
        }

        var payload: [String: Any] = [
            "callBack": callBack,
            "key": key,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]

        if !includeData {
            sink(payload)
            return
        }

        guard let ref = geoFireRef else {
            sink(payload)
            return
        }

        ref.child(key).observeSingleEvent(of: .value, with: { snapshot in
            if
                let value = snapshot.value as? [String: Any],
                let data = value["data"] as? [String: Any]
            {
                payload["data"] = data
            }
            sink(payload)
        }, withCancel: { _ in
            sink(payload)
        })
    }

}
