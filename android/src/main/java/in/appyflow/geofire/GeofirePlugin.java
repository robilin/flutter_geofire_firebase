package in.appyflow.geofire;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;


import androidx.annotation.NonNull;

import com.firebase.geofire.GeoFire;
import com.firebase.geofire.GeoLocation;
import com.firebase.geofire.GeoQuery;
import com.firebase.geofire.GeoQueryEventListener;
import com.firebase.geofire.LocationCallback;
import com.google.firebase.database.DataSnapshot;
import com.google.firebase.database.DatabaseError;
import com.google.firebase.database.DatabaseReference;
import com.google.firebase.database.FirebaseDatabase;
import com.google.firebase.database.ValueEventListener;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;


import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * GeofirePlugin
 */
public class GeofirePlugin implements FlutterPlugin,MethodCallHandler, EventChannel.StreamHandler {

    private static final String PREFS_NAME = "flutter_geofire";
    private static final String PENDING_WRITES_KEY = "pending_writes";
    private static boolean persistenceConfigured = false;

    GeoFire geoFire;
    DatabaseReference databaseReference;
    static MethodChannel channel;
    static EventChannel eventChannel;
    private EventChannel.EventSink events;
    private Context applicationContext;

    /**
     * Plugin registration.
     */

    public static void pluginInit(BinaryMessenger messenger){
        GeofirePlugin geofirePlugin = new GeofirePlugin();

        channel = new MethodChannel(messenger, "geofire");
        channel.setMethodCallHandler(geofirePlugin);

        eventChannel = new EventChannel(messenger, "geofireStream");
        eventChannel.setStreamHandler(geofirePlugin);

    }

//    public static void registerWith(Registrar registrar) {
//        pluginInit(registrar.messenger());
//    }

    @Override
    public void onMethodCall(MethodCall call, final Result result) {

        Log.i("TAG", call.method.toString());

        if (call.method.equals("GeoFire.start")) {

            configurePersistence();

            databaseReference = FirebaseDatabase.getInstance().getReference(call.argument("path").toString());
            geoFire = new GeoFire(databaseReference);
            flushPendingWrites();

            if (geoFire.getDatabaseReference() != null) {
                result.success(true);
            } else
                result.success(false);
        } else if (call.method.equals("setLocation")) {

            final String id = call.argument("id").toString();
            final double lat = Double.parseDouble(call.argument("lat").toString());
            final double lng = Double.parseDouble(call.argument("lng").toString());
            final Map<String, Object> request = createWriteRequest(id, lat, lng, new HashMap<String, Object>());

            enqueuePendingWrite(request);

            writeLocationWithData(request, new WriteCompletion() {
                @Override
                public void onComplete(boolean isSuccess) {
                    if (isSuccess) {
                        dequeuePendingWrite(request.get("requestId").toString());
                        result.success(true);
                    } else {
                        result.success(false);
                    }
                }
            });


        } else if (call.method.equals("setLocationWithData") || call.method.equals("setLocationWithMetadata")) {

            final String id = call.argument("id").toString();
            final double lat = Double.parseDouble(call.argument("lat").toString());
            final double lng = Double.parseDouble(call.argument("lng").toString());
            final Map<String, Object> additionalData = sanitizeAdditionalData(call.argument("data"));
            final Map<String, Object> request = createWriteRequest(id, lat, lng, additionalData);

            enqueuePendingWrite(request);

            writeLocationWithData(request, new WriteCompletion() {
                @Override
                public void onComplete(boolean isSuccess) {
                    if (isSuccess) {
                        dequeuePendingWrite(request.get("requestId").toString());
                        result.success(true);
                    } else {
                        result.success(false);
                    }
                }
            });


        } else if (call.method.equals("removeLocation")) {

            geoFire.removeLocation(call.argument("id").toString(), new GeoFire.CompletionListener() {
                @Override
                public void onComplete(String key, DatabaseError error) {

                    if (error != null) {
                        result.success(false);
                    } else {
                        result.success(true);
                    }

                }
            });


        } else if (call.method.equals("getLocation")) {

            geoFire.getLocation(call.argument("id").toString(), new LocationCallback() {
                @Override
                public void onLocationResult(String key, GeoLocation location) {
                    HashMap<String, Object> map = new HashMap<>();
                    if (location != null) {


                        map.put("lat", location.latitude);
                        map.put("lng", location.longitude);
                        map.put("error", null);

                    } else {


                        map.put("error", String.format("There is no location for key %s in GeoFire", key));

                    }

                    result.success(map);
                }

                @Override
                public void onCancelled(DatabaseError databaseError) {
                    HashMap<String, Object> map = new HashMap<>();
                    map.put("error", "There was an error getting the GeoFire location: " + databaseError);

                    result.success(map);
                }
            });


        } else if (call.method.equals("queryAtLocation")) {
            final Boolean includeDataArg = call.argument("includeData");
            final boolean includeData = includeDataArg != null && includeDataArg;
            geoFireArea(Double.parseDouble(call.argument("lat").toString()), Double.parseDouble(call.argument("lng").toString()), result, Double.parseDouble(call.argument("radius").toString()), includeData);
        } else if (call.method.equals("stopListener")) {

            if (geoQuery != null) {
                geoQuery.removeAllListeners();
            }

            result.success(true);
        } else {
            result.notImplemented();
        }
    }

    GeoQuery geoQuery;

    HashMap<String, Object> hashMap = new HashMap<>();

    @SuppressWarnings("unchecked")
    private Map<String, Object> sanitizeAdditionalData(Object metadataRaw) {
        Map<String, Object> sanitized = new HashMap<>();

        if (!(metadataRaw instanceof Map)) {
            return sanitized;
        }

        Map<Object, Object> metadata = (Map<Object, Object>) metadataRaw;
        for (Map.Entry<Object, Object> entry : metadata.entrySet()) {
            if (entry.getKey() == null) {
                continue;
            }

            String key = entry.getKey().toString();
            if ("g".equals(key) || "l".equals(key)) {
                continue;
            }
            sanitized.put(key, entry.getValue());
        }

        return sanitized;
    }

    private void configurePersistence() {
        if (persistenceConfigured) {
            return;
        }

        try {
            FirebaseDatabase.getInstance().setPersistenceEnabled(true);
        } catch (Exception e) {
            Log.w("GeofirePlugin", "Could not enable Firebase persistence", e);
        } finally {
            persistenceConfigured = true;
        }
    }

    private SharedPreferences getPrefs() {
        if (applicationContext == null) {
            return null;
        }
        return applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    private List<Map<String, Object>> loadPendingWrites() {
        List<Map<String, Object>> requests = new ArrayList<>();
        SharedPreferences prefs = getPrefs();
        if (prefs == null) {
            return requests;
        }

        String raw = prefs.getString(PENDING_WRITES_KEY, null);
        if (raw == null || raw.isEmpty()) {
            return requests;
        }

        try {
            JSONArray arr = new JSONArray(raw);
            for (int i = 0; i < arr.length(); i++) {
                Object item = arr.opt(i);
                if (!(item instanceof JSONObject)) {
                    continue;
                }
                requests.add(jsonObjectToMap((JSONObject) item));
            }
        } catch (JSONException e) {
            Log.w("GeofirePlugin", "Could not parse pending writes", e);
        }

        return requests;
    }

    private void savePendingWrites(List<Map<String, Object>> requests) {
        SharedPreferences prefs = getPrefs();
        if (prefs == null) {
            return;
        }

        JSONArray arr = new JSONArray();
        for (Map<String, Object> request : requests) {
            arr.put(new JSONObject(request));
        }

        prefs.edit().putString(PENDING_WRITES_KEY, arr.toString()).apply();
    }

    private void enqueuePendingWrite(Map<String, Object> request) {
        List<Map<String, Object>> requests = loadPendingWrites();
        requests.add(request);
        savePendingWrites(requests);
    }

    private void dequeuePendingWrite(String requestId) {
        List<Map<String, Object>> requests = loadPendingWrites();
        Iterator<Map<String, Object>> iterator = requests.iterator();
        while (iterator.hasNext()) {
            Map<String, Object> request = iterator.next();
            Object value = request.get("requestId");
            if (value != null && value.toString().equals(requestId)) {
                iterator.remove();
                break;
            }
        }
        savePendingWrites(requests);
    }

    private void flushPendingWrites() {
        if (geoFire == null || databaseReference == null) {
            return;
        }

        final List<Map<String, Object>> requests = loadPendingWrites();
        for (final Map<String, Object> request : requests) {
            writeLocationWithData(request, new WriteCompletion() {
                @Override
                public void onComplete(boolean isSuccess) {
                    if (isSuccess && request.get("requestId") != null) {
                        dequeuePendingWrite(request.get("requestId").toString());
                    }
                }
            });
        }
    }

    @SuppressWarnings("unchecked")
    private void writeLocationWithData(final Map<String, Object> request, final WriteCompletion completion) {
        if (geoFire == null || databaseReference == null) {
            completion.onComplete(false);
            return;
        }

        final String id = String.valueOf(request.get("id"));
        final double lat = Double.parseDouble(String.valueOf(request.get("lat")));
        final double lng = Double.parseDouble(String.valueOf(request.get("lng")));
        final Map<String, Object> additionalData = request.get("data") instanceof Map
                ? (Map<String, Object>) request.get("data")
                : new HashMap<String, Object>();

        geoFire.setLocation(id, new GeoLocation(lat, lng), new GeoFire.CompletionListener() {
            @Override
            public void onComplete(String key, DatabaseError error) {
                if (error != null) {
                    completion.onComplete(false);
                    return;
                }

                if (additionalData.isEmpty()) {
                    completion.onComplete(true);
                    return;
                }

                Map<String, Object> payload = new HashMap<>();
                payload.put("data", additionalData);

                databaseReference.child(id).updateChildren(payload, new DatabaseReference.CompletionListener() {
                    @Override
                    public void onComplete(DatabaseError metadataError, DatabaseReference ref) {
                        completion.onComplete(metadataError == null);
                    }
                });
            }
        });
    }

    private interface WriteCompletion {
        void onComplete(boolean isSuccess);
    }

    private Map<String, Object> createWriteRequest(String id, double lat, double lng, Map<String, Object> data) {
        final Map<String, Object> request = new HashMap<>();
        request.put("requestId", UUID.randomUUID().toString());
        request.put("id", id);
        request.put("lat", lat);
        request.put("lng", lng);
        request.put("data", data);
        return request;
    }

    private Map<String, Object> jsonObjectToMap(JSONObject jsonObject) throws JSONException {
        Map<String, Object> map = new HashMap<>();
        Iterator<String> keys = jsonObject.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            Object value = jsonObject.get(key);
            map.put(key, jsonToJava(value));
        }
        return map;
    }

    private List<Object> jsonArrayToList(JSONArray array) throws JSONException {
        List<Object> list = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            list.add(jsonToJava(array.get(i)));
        }
        return list;
    }

    private Object jsonToJava(Object value) throws JSONException {
        if (value == JSONObject.NULL) {
            return null;
        }
        if (value instanceof JSONObject) {
            return jsonObjectToMap((JSONObject) value);
        }
        if (value instanceof JSONArray) {
            return jsonArrayToList((JSONArray) value);
        }
        return value;
    }


    private void geoFireArea(final double latitude, double longitude, final Result result, double radius,
                             final boolean includeData) {
        try {

            final ArrayList<String> arrayListKeys = new ArrayList<>();

            if (geoQuery != null) {
                geoQuery.setLocation(new GeoLocation(latitude, longitude), radius);
            } else {
                geoQuery = geoFire.queryAtLocation(new GeoLocation(latitude, longitude), radius);
            }

            geoQuery.addGeoQueryEventListener(new GeoQueryEventListener() {
                @Override
                public void onKeyEntered(String key, GeoLocation location) {
                    arrayListKeys.add(key);
                    emitQueryEventWithData("onKeyEntered", key, location, null, includeData);

                }

                @Override
                public void onKeyExited(String key) {
                    arrayListKeys.remove(key);
                    emitQueryEventWithData("onKeyExited", key, null, null, includeData);

                }

                @Override
                public void onKeyMoved(String key, GeoLocation location) {
                    emitQueryEventWithData("onKeyMoved", key, location, null, includeData);

                }

                @Override
                public void onGeoQueryReady() {
//                    geoQuery.removeAllListeners();
//                    result.success(arrayListKeys);

                    if (events != null) {
                        HashMap<String, Object> readyPayload = new HashMap<>();
                        readyPayload.put("callBack", "onGeoQueryReady");
                        readyPayload.put("result", arrayListKeys);
                        events.success(readyPayload);

                    } else {
                        geoQuery.removeAllListeners();
                    }

                }

                @Override
                public void onGeoQueryError(DatabaseError error) {

                    if (events != null) {

                        events.error("Error ", "GeoQueryError", error);
                    } else {
                        geoQuery.removeAllListeners();
                    }


                }
            });
        } catch (Exception e) {
            e.printStackTrace();
            result.error("Error ", "General Error", e);
        }
    }

    private void emitQueryEventWithData(final String callback, final String key, final GeoLocation location,
                                        final Map<String, Object> additionalPayload,
                                        final boolean includeData) {
        if (events == null) {
            if (geoQuery != null) {
                geoQuery.removeAllListeners();
            }
            return;
        }

        final HashMap<String, Object> payload = new HashMap<>();
        payload.put("callBack", callback);
        payload.put("key", key);
        if (location != null) {
            payload.put("latitude", location.latitude);
            payload.put("longitude", location.longitude);
        }
        if (additionalPayload != null) {
            payload.putAll(additionalPayload);
        }

        if (!includeData || databaseReference == null || key == null) {
            events.success(payload);
            return;
        }

        databaseReference.child(key).addListenerForSingleValueEvent(new ValueEventListener() {
            @Override
            public void onDataChange(@NonNull DataSnapshot snapshot) {
                Object dataValue = snapshot.child("data").getValue();
                if (dataValue instanceof Map) {
                    payload.put("data", dataValue);
                }
                events.success(payload);
            }

            @Override
            public void onCancelled(@NonNull DatabaseError error) {
                events.success(payload);
            }
        });
    }

    @Override
    public void onListen(Object o, EventChannel.EventSink eventSink) {
        events = eventSink;
    }

    @Override
    public void onCancel(Object o) {

        geoQuery.removeAllListeners();
        events = null;

    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        pluginInit(binding.getBinaryMessenger());
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = null;
        channel.setMethodCallHandler(null);
        eventChannel.setStreamHandler(null);
    }
}