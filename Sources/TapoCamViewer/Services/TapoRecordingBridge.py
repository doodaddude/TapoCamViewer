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
            results_raw = tapo.getRecordings(date_str)
            clips = []
            for item in results_raw:
                for k, v in item.items():
                    if "startTime" in v and "endTime" in v:
                        clips.append({
                            "startTime": v["startTime"],
                            "endTime": v["endTime"],
                            "duration": v["endTime"] - v["startTime"],
                            "type": v.get("vedio_type", 1)
                        })
            print(json.dumps({"status": "ok", "date": date_str, "clips": clips}))

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
