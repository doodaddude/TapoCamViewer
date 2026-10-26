#!/usr/bin/env python3
import sys, json, os, datetime, urllib3
urllib3.disable_warnings()

# Fix LibreSSL cipher requirements for macOS
try:
    for p in [
        os.path.expanduser("~/Library/Python/3.9/lib/python/site-packages/pytapo/transport/pytapo/TlsAdapter.py"),
        os.path.expanduser("~/Library/Python/3.9/lib/python/site-packages/pytapo/transport/kasa/kasa.py")
    ]:
        if os.path.exists(p):
            with open(p, "r") as f:
                c = f.read()
            if "ALL:@SECLEVEL=0" in c:
                with open(p, "w") as f:
                    f.write(c.replace("ALL:@SECLEVEL=0", "ALL:!aNULL:!eNULL"))
except Exception:
    pass

from pytapo import Tapo

# ------------------------------------------------------------------
# Event type mapping from alarm_type integer codes
# Priority order (highest = most specific / interesting first)
# ------------------------------------------------------------------
EVENT_TYPE_PRIORITY = [6, 9, 8, 5, 4, 7, 11, 12, 13, 10, 3, 2, 1]  # highest priority first

EVENT_TYPE_INFO = {
    1:  {"label": "Continuous",      "icon": "film",                               "color": "gray"},
    2:  {"label": "Motion",          "icon": "sensor.tag.radiowaves.forward.fill",  "color": "orange"},
    3:  {"label": "Tamper",          "icon": "shield.exclamationmark.fill",         "color": "red"},
    4:  {"label": "Line Crossing",   "icon": "arrow.left.and.right.square",         "color": "cyan"},
    5:  {"label": "Area Intrusion",  "icon": "bell.badge.fill",                    "color": "red"},
    6:  {"label": "Person",          "icon": "figure.walk",                         "color": "purple"},
    7:  {"label": "Baby Cry",        "icon": "waveform.path.ecg",                   "color": "pink"},
    8:  {"label": "Vehicle",         "icon": "car.fill",                            "color": "blue"},
    9:  {"label": "Pet",             "icon": "pawprint.fill",                       "color": "green"},
    10: {"label": "Ring Alarm",      "icon": "bell.ring.fill",                      "color": "yellow"},
    11: {"label": "Bark",            "icon": "speaker.wave.3.fill",                 "color": "brown"},
    12: {"label": "Meow",            "icon": "cat.fill",                            "color": "orange"},
    13: {"label": "Glass Break",     "icon": "sparkles.rectangle.stack.fill",       "color": "red"},
}

def classify_clip(clip_start, clip_end, events):
    """
    Given a clip's [startTime, endTime] and a list of detection events,
    find all overlapping events and return the highest-priority event type info.
    Falls back to 'Continuous' (type 1) if no events overlap.
    """
    overlap_types = set()
    slack = 5  # seconds of tolerance on clip boundaries
    for ev in events:
        ev_start = ev.get("start_time", 0)
        ev_end   = ev.get("end_time", ev_start)
        alarm_type = ev.get("alarm_type", 2)
        # Overlap check: events overlap the clip window if they don't end before it starts and don't start after it ends
        if not (ev_end < clip_start - slack or ev_start > clip_end + slack):
            overlap_types.add(alarm_type)

    # Pick highest-priority event code
    for code in EVENT_TYPE_PRIORITY:
        if code in overlap_types:
            info = EVENT_TYPE_INFO.get(code, EVENT_TYPE_INFO[2])
            return code, info["label"], info["icon"], info["color"]

    # Default: use the generic SD clip type if no events matched
    default_info = EVENT_TYPE_INFO[1]
    return 1, default_info["label"], default_info["icon"], default_info["color"]

def safe_call(func, *args, **kwargs):
    try:
        return func(*args, **kwargs)
    except Exception as e:
        return {"error": str(e), "unsupported": True}

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No action specified"}))
        return

    action = sys.argv[1]

    # Read credentials & parameters dynamically from stdin JSON to avoid command-line argument leakage
    try:
        raw_in = sys.stdin.read()
        input_data = json.loads(raw_in) if raw_in.strip() else {}
    except Exception as e:
        print(json.dumps({"error": f"Invalid input JSON: {e}"}))
        return

    ip = input_data.get("ip")
    user = input_data.get("user")
    password = input_data.get("password")

    if not ip or not user or not password:
        print(json.dumps({"error": "Missing required camera connection info"}))
        return

    try:
        tapo = Tapo(ip, user, password)

        if action == "list_dates":
            dates_raw = tapo.getRecordingsList()
            dates = []
            for item in dates_raw:
                for k, v in item.items():
                    if "date" in v:
                        dates.append(v["date"])
            print(json.dumps({"status": "ok", "dates": dates}))

        elif action == "get_recordings":
            date_str = input_data.get("date", datetime.datetime.now().strftime("%Y%m%d"))

            # Parse the date string to a UTC midnight range for event lookup
            date_obj = datetime.datetime.strptime(date_str, "%Y%m%d")
            day_start_ts = int(date_obj.timestamp())
            day_end_ts   = int((date_obj + datetime.timedelta(hours=23, minutes=59, seconds=59)).timestamp())

            # Fetch SD card clip list for the day
            results_raw = tapo.getRecordings(date_str)

            # Fetch detection events for the entire day to enrich each clip
            events = []
            try:
                events = tapo.getEvents(startTime=day_start_ts, endTime=day_end_ts)
            except Exception as ev_err:
                # Non-fatal: we'll fall back to generic labels if events unavailable
                pass

            clips = []
            for item in results_raw:
                for k, v in item.items():
                    if "startTime" in v and "endTime" in v:
                        st = v["startTime"]
                        et = v["endTime"]
                        raw_type = v.get("vedio_type", 1)

                        # Classify using detection events
                        event_code, event_label, icon_name, color = classify_clip(st, et, events)

                        # If the clip is marked as continuous (type 1) and no events overlap → keep Continuous
                        # If the raw SD type is motion (2) but no specific event found → label as Motion
                        if event_code == 1 and raw_type == 2:
                            info = EVENT_TYPE_INFO[2]
                            event_code, event_label, icon_name, color = 2, info["label"], info["icon"], info["color"]

                        clips.append({
                            "startTime":  st,
                            "endTime":    et,
                            "duration":   et - st,
                            "type":       raw_type,
                            "eventCode":  event_code,
                            "eventType":  event_label,
                            "iconName":   icon_name,
                            "color":      color,
                        })
            print(json.dumps({"status": "ok", "date": date_str, "clips": clips, "eventCount": len(events)}))

        elif action == "get_alarm_and_detections":
            # Query alarm status & all detection capabilities
            alarm_info = safe_call(tapo.getAlarm)
            motion_info = safe_call(tapo.getMotionDetection)
            person_info = safe_call(tapo.getPersonDetection)
            vehicle_info = safe_call(tapo.getVehicleDetection)
            pet_info = safe_call(tapo.getPetDetection)
            tamper_info = safe_call(tapo.getTamperDetection)
            baby_cry_info = safe_call(tapo.getBabyCryDetection)
            bark_info = safe_call(tapo.getBarkDetection)
            glass_info = safe_call(tapo.getGlassBreakDetection)

            result = {
                "status": "ok",
                "alarm": alarm_info,
                "motion": motion_info,
                "person": person_info,
                "vehicle": vehicle_info,
                "pet": pet_info,
                "tamper": tamper_info,
                "baby_cry": baby_cry_info,
                "bark": bark_info,
                "glass": glass_info
            }
            print(json.dumps(result))

        elif action == "set_alarm":
            # Expected params: enabled (bool), soundEnabled (bool), lightEnabled (bool), alarmVolume (str/int), alarmDuration (str/int)
            enabled = input_data.get("enabled", True)
            sound_enabled = input_data.get("soundEnabled", True)
            light_enabled = input_data.get("lightEnabled", True)
            volume = input_data.get("alarmVolume", None)
            duration = input_data.get("alarmDuration", None)

            # Ensure at least one mode is active if enabled
            if enabled and not sound_enabled and not light_enabled:
                sound_enabled = True

            res = tapo.setAlarm(
                enabled=enabled,
                soundEnabled=sound_enabled,
                lightEnabled=light_enabled,
                alarmVolume=volume,
                alarmDuration=duration
            )
            print(json.dumps({"status": "ok", "result": res}))

        elif action == "set_detection":
            # Expected params: target ("person", "motion", "vehicle", "pet", "tamper", "baby_cry", etc), enabled (bool), sensitivity (int/str)
            target = input_data.get("target")
            enabled = input_data.get("enabled", True)
            sensitivity = input_data.get("sensitivity", None)

            if target == "person":
                res = tapo.setPersonDetection(enabled=enabled, sensitivity=sensitivity or False)
            elif target == "motion":
                res = tapo.setMotionDetection(enabled=enabled, sensitivity=sensitivity or False)
            elif target == "vehicle":
                res = tapo.setVehicleDetection(enabled=enabled, sensitivity=sensitivity or False)
            elif target == "pet":
                res = tapo.setPetDetection(enabled=enabled, sensitivity=sensitivity or False)
            elif target == "tamper":
                res = tapo.setTamperDetection(enabled=enabled, sensitivity=sensitivity or False)
            elif target == "baby_cry":
                res = tapo.setBabyCryDetection(enabled=enabled, sensitivity=sensitivity or False)
            elif target == "bark":
                res = tapo.setBarkDetection(enabled=enabled, sensitivity=sensitivity or False)
            elif target == "glass":
                res = tapo.setGlassBreakDetection(enabled=enabled, sensitivity=sensitivity or False)
            else:
                print(json.dumps({"error": f"Unsupported detection target: {target}"}))
                return

            print(json.dumps({"status": "ok", "target": target, "result": res}))

        else:
            print(json.dumps({"error": f"Unknown action: {action}"}))

    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    main()
