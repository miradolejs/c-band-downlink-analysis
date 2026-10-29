import SoapySDR
from SoapySDR import *
import numpy as np
import time
from datetime import datetime
import os
import json
import serial

from datetime import timedelta

from shared_state import state, lock

import shutil

def handle_safe_swap():
    global current_base_dir, use_ssd
    
    if os.path.exists("/tmp/swap_flag"):
        with lock:
            state["swap_requested"] = True
        os.remove("/tmp/swap_flag")
        
    if os.path.exists("/tmp/confirm_swap_flag"):
        with lock:
            state["safe_to_remove"] = False
            state["force_ssd"] = False
            state["swap_requested"] = False
            
            if is_disk_available(HDD_MOUNT):
            
                current_base_dir = HDD_DIR
                use_ssd = False
                
                state["pending_transfer"] = True
                
                print("Disk se vrátil -> přepínám na HDD")
                
                state["last_log"] = "Disk se vrátil -> přepínám na HDD"
                
        save_status()

        os.remove("/tmp/confirm_swap_flag")

    should_activate_swap = False

    with lock:
        swap = state["swap_requested"]
        idle = state["idle"]

        if swap and idle:

            print("SAFE SWAP: flush filesystem...")

            state["last_log"] = "SAFE SWAP: flush filesystem..."

            should_activate_swap = True

    if should_activate_swap:

        os.sync()

        with lock:

            print("SAFE SWAP: můžeš odpojit disk")

            state["last_log"] = "SAFE SWAP: můžeš odpojit disk"

            state["safe_to_remove"] = True
            state["swap_requested"] = False
            state["force_ssd"] = True

            current_base_dir = SSD_DIR
            use_ssd = True
    
        save_status()

def is_disk_available(path):
    return os.path.ismount(path)
    
# ===== PŘESUN DAT Z SSD =====

def move_data_to_hdd():

    oldest_file = None

    for root, dirs, files in os.walk(SSD_DIR):
        for file in files:

            if file.endswith(".raw"):

                path = os.path.join(root, file)

                if oldest_file is None or os.path.getmtime(path) < os.path.getmtime(oldest_file):
                    oldest_file = path

    if oldest_file is None:
        return False

    filename = os.path.basename(oldest_file)

    date_folder = filename.split("_")[-1].replace(".raw", "")

    dst_dir = os.path.join(HDD_DIR, date_folder)

    os.makedirs(dst_dir, exist_ok=True)

    dst = os.path.join(dst_dir, filename)

    try:
        shutil.move(oldest_file, dst)

        json_src = oldest_file.replace(".raw", ".json")
        json_dst = dst.replace(".raw", ".json")

        if os.path.exists(json_src):
            shutil.move(json_src, json_dst)

        print("Přesunut:", filename)
        with lock:
            state["last_log"] = f"Přesunut: {filename}"

        save_status()

        return True

    except Exception as e:
        print("Chyba přesunu:", e)

        return None

# ====== FUNKCE STAV DISKU ======

def get_disk_usage(path):
    total, used, free = shutil.disk_usage(path)

    return {
        "total_gb": total / 1e9,
        "used_gb": used / 1e9,
        "free_gb": free / 1e9,
        "percent_used": (used / total) * 100
    }

# ====== FUNKCE ODHAD ZAPLNĚNÍ DISKU =======

def estimate_time_remaining(free_bytes, write_speed_bytes_per_sec):
    seconds = free_bytes / write_speed_bytes_per_sec
    hours = seconds / 3600
    return hours
    
def save_status():
    with lock:
        status_copy = dict(state)

    tmp_path = "/tmp/recorder_status.tmp"
    final_path = "/tmp/recorder_status.json"

    with open(tmp_path, "w") as f:
        json.dump(status_copy, f)

    os.replace(tmp_path, final_path)

# ====== DEFINICE DATUMŮ A ČASŮ JEDNOTLIVÝCH FÁZÍ =====

START_PHASE1 = datetime(2026, 10, 15, 23, 55, 0)
START_PHASE2 = datetime(2026, 10, 16, 0, 0, 0)
END_TIME     = datetime(2026, 10, 25, 23, 59, 0)

# ===== PARAMETRY =====
SAMPLE_RATE = 10e6
FREQ = 1312e6
GAIN = 0
BLOCK_SIZE = 4096

# ===== DEFINICE CEST =====

HDD_MOUNT = "/media/admin/Elements"
HDD_DIR = "/media/admin/Elements/iq_data"

SSD_DIR = "/home/admin/iq_recorder/ssd_buffer"

os.makedirs(SSD_DIR, exist_ok=True)

current_base_dir = HDD_DIR
use_ssd = False

with lock:
    state["safe_to_remove"] = False
    state["swap_requested"] = False

# ===== SDR INIT =====
sdr = SoapySDR.Device()

sdr.writeSetting("clock_source", "1")

sdr.setSampleRate(SOAPY_SDR_RX, 0, SAMPLE_RATE)
sdr.setFrequency(SOAPY_SDR_RX, 0, FREQ)
sdr.setGain(SOAPY_SDR_RX, 0, GAIN)


print("Sample rate real:", sdr.getSampleRate(SOAPY_SDR_RX, 0))

stream = sdr.setupStream(SOAPY_SDR_RX, SOAPY_SDR_CF32)

buff = np.empty(BLOCK_SIZE * 2, dtype=np.float32)

# ===== ENV SENSOR SERIAL =====

sensor_serial = None

try:
    sensor_serial = serial.Serial(
        "/dev/ttyUSB0",
        115200,
        timeout=0.2
    )

    print("Arduino ENV serial připojen")
    time.sleep(2)
    sensor_serial.reset_input_buffer()

except Exception as e:
    print("Arduino ENV serial nenalezen:", e)

# ===== ENV READ =====

def read_environment():

    if sensor_serial is None:
        return {
            "temperature_c": None,
            "humidity_percent": None,
            "env_valid": False
        }

    try:

        line = ""

        while sensor_serial.in_waiting > 0:
            line = sensor_serial.readline().decode(errors="ignore").strip()
            
        if line == "":
            line = sensor_serial.readline().decode(errors="ignore").strip()
        
        print("ENV RAW:", repr(line))

        if line == "":
            return {
                "temperature_c": None,
                "humidity_percent": None,
                "env_valid": False
            }

        if not line.startswith("ENV:"):
            return {
                "temperature_c": None,
                "humidity_percent": None,
                "env_valid": False
            }

        line = line.replace("ENV:", "")

        parts = line.split(",")

        temperature = float(parts[0].split(":")[1])
        humidity = float(parts[1].split(":")[1])

        return {
            "temperature_c": temperature,
            "humidity_percent": humidity,
            "env_valid": True
        }

    except Exception as e:

        print("ENV read error:", e)

        return {
            "temperature_c": None,
            "humidity_percent": None,
            "env_valid": False
        }

# ===== FILE PREP =====
def create_folder(base_dir):
    now = datetime.now()
    folder_name = now.strftime("%d%m%y")
    path = os.path.join(base_dir, folder_name)
    os.makedirs(path, exist_ok=True)
    return path


# ===== RECORD LOOP =====
def record_once(duration_sec, measurement_id):
    
    with lock:
        state["idle"] = False
        
    sdr.activateStream(stream)
    
    usage = None
    
    try:
    
        with lock:
            state["last_log"] = "Spouštím záznam"
        
        save_status()
    
        write_error = False
    
        global current_base_dir, use_ssd
    
        disk_now = is_disk_available(HDD_MOUNT)

        with lock:
            force_ssd = state.get("force_ssd", False)

        if not disk_now or force_ssd:
            if not use_ssd:
                print("Disk zmizel → přepínám na SSD")
                current_base_dir = SSD_DIR
                use_ssd = True
                
                with lock:
                    state["last_log"] = "Disk zmizel → přepínám na SSD"
                    state["use_ssd"] = True
                    state["disk_available"] = False
                    
                save_status()
                
                

            # kontrola SSD místa
            usage = shutil.disk_usage(SSD_DIR)
            free_gb = usage.free / 1e9

            if usage.free < 5 * 1024**3:
                print(f"!!! SSD DOCHÁZÍ MÍSTO: {free_gb:.2f} GB !!!")
                with lock:
                    state["last_log"] = f"!!! SSD DOCHÁZÍ MÍSTO: {free_gb:.2f} GB !!!"
        
            if usage.free < 1 * 1024**3:
                print("!!! SSD PLNÉ – SAFE SWAP !!!")
                with lock:
                    state["last_log"] = "!!! SSD PLNÉ – SAFE SWAP !!! čekám na zásah"
                    state["swap_requested"] = True
                save_status()
                return
    
        with lock:
            state["disk_available"] = (
                disk_now and not write_error
            )
            state["use_ssd"] = use_ssd
            state["current_dir"] = current_base_dir

        folder = create_folder(current_base_dir)

        timestamp = datetime.now().strftime("%H%M%S_%d%m%y")
        filename = f"{measurement_id}_{timestamp}"

        raw_path = os.path.join(folder, filename + ".raw")
        json_path = os.path.join(folder, filename + ".json")

        with open(raw_path, "wb") as f:

            print("Nahrávám:", filename, "čas:", datetime.now())
            with lock:
                state["last_log"] = f"Nahrávám: {filename} čas: {datetime.now()}"
            
            save_status()

            start_time = time.time()
            total_samples = 0
            
            last_swap_check = 0

            while time.time() - start_time < duration_sec:
            
                if time.time() - last_swap_check > 0.5:
                    handle_safe_swap()
                    last_swap_check = time.time()
            

                sr = sdr.readStream(stream, [buff], BLOCK_SIZE)
    
                if sr.ret > 0:
                    iq = np.clip(buff[:sr.ret * 2], -1.0, 1.0)
                    iq_int16 = (iq * 32767).astype(np.int16)
                
                    try:
                        f.write(iq_int16.tobytes())
                        if total_samples > 0 and total_samples % (BLOCK_SIZE * 500) == 0:
                            f.flush()
                            os.fsync(f.fileno())
                    except OSError as e:
                        print("!!! CHYBA ZÁPISU – DISK ODPOJEN !!!", e)
                        with lock:
                            state["last_log"] = "!!! CHYBA ZÁPISU – DISK ODPOJEN !!!"
                            state["disk_available"] = False
                        save_status()
                        write_error = True
                        break
                    
                    total_samples += sr.ret
                
                elif sr.ret < 0:
                    print("SDR ERROR:", sr.ret)

                    with lock:
                        state["last_log"] = f"SDR ERROR: {sr.ret}"

                    save_status()
    
        if write_error:
            print("Záznam předčasně ukončen")
            
        env_data = read_environment()

        metadata = {
            "start_iso": datetime.fromtimestamp(start_time).isoformat(),
            "sample_rate": SAMPLE_RATE,
            "center_freq": FREQ,
            "gain": GAIN,
            "format": "int16",
            "samples_recorded": int(total_samples),
            "start_unix": start_time,
            "write_error": write_error,
            
            "temperature_c": env_data["temperature_c"],
            "humidity_percent": env_data["humidity_percent"],
            "env_valid": env_data["env_valid"]
        }
    
        with open(json_path, "w") as jf:
            json.dump(metadata, jf, indent=4)

# ===== POUŽITÍ FUNKCE STAVU DISKU A ODHADU ZAPLNĚNÍ ====

        print("Hotovo:", raw_path)
    
        usage = get_disk_usage(current_base_dir)

        print(f"Disk: {usage['percent_used']:.2f}% zaplněno")
        print(f"Volno: {usage['free_gb']:.1f} GB")
        
    finally:
        sdr.deactivateStream(stream)
        
        with lock:
            state["idle"] = True
        
        save_status()

    if usage is not None:

        write_speed = 32 * 1024 * 1024

        hours_left = estimate_time_remaining(
            usage["free_gb"] * 1e9,
            write_speed
        )

        print(f"Odhad: {hours_left:.1f} hodin do zaplnění")
        
    # opakovaně zkus swap (spolehlivější)
    for _ in range(3):
        handle_safe_swap()
        time.sleep(0.05)

# ====== CHEDULER (HLAVNÍ LOGIKA) =======

try:

    measurement_id = 1

    print("Scheduler běží...")


    print(f"Čekám na START_PHASE1: {START_PHASE1}")

    while datetime.now() < START_PHASE1:
        handle_safe_swap()
    
        with lock:
            remaining = (START_PHASE1 - datetime.now()).total_seconds()

            state["last_log"] = f"Start za {int(remaining)} s"
    
        time.sleep(0.5)

    print("START fáze 1")

# ===== FÁZE 1 =====
    now = datetime.now()
    next_run = START_PHASE1

    while next_run < now:
        next_run += timedelta(minutes=1)
    
    swap_wait_printed = False

    while datetime.now() < START_PHASE2:
    
        should_save = False
    
        with lock:
            if state["safe_to_remove"] and not state.get("force_ssd") and is_disk_available(HDD_MOUNT) and state["idle"]:
                print("Disk zpět → návrat do normálu")
                state["last_log"] = "Disk zpět → návrat do normálu"
                state["safe_to_remove"] = False
                state["force_ssd"] = False
            
                should_save = True
            
        if should_save:
            save_status()
            
    
    
        print("Plánovaný start:", next_run)
    

        while datetime.now() < next_run:
            handle_safe_swap()
        
            should_save = False
        
            with lock:
                if state["swap_requested"] and not swap_wait_printed:
                    print("SAFE SWAP: čekám na dokončení záznamu")

                    state["last_log"] = "SAFE SWAP: čekám na dokončení záznamu"

                    swap_wait_printed = True
                    should_save = True

            if should_save:
                save_status()

            time.sleep(0.1)
    
        record_once(50, measurement_id)
    
        swap_wait_printed = False
    
        handle_safe_swap()
        
        measurement_id += 1

        next_run += timedelta(minutes=1)

    print("Přechod na fázi 2...")

# ===== FÁZE 2 =====
    now = datetime.now()
    next_run = START_PHASE2

    while next_run < now:
        next_run += timedelta(minutes=10)

    swap_wait_printed = False

    while datetime.now() < END_TIME:
    
        should_save = False
    
        with lock:
            if state["safe_to_remove"] and not state.get("force_ssd") and is_disk_available(HDD_MOUNT) and state["idle"]:
                print("Disk zpět → návrat do normálu")
                state["last_log"] = "Disk zpět → návrat do normálu"
                state["safe_to_remove"] = False
                state["force_ssd"] = False
            
                should_save = True
            
        if should_save:
            save_status()
    
        print("Plánovaný start:", next_run)
    

        while datetime.now() < next_run:
        
            handle_safe_swap()

            should_transfer = False

            with lock:
                pending = state["pending_transfer"]
                idle = state["idle"]

            if pending and idle:
                should_transfer = True

            if should_transfer:

                print("Přesouvám SSD buffer na HDD...")
            
                with lock:
                    state["transfer_in_progress"] = True

                save_status()

                try:
                    handle_safe_swap()

                    with lock:
                        force_ssd = state["force_ssd"]

                    if force_ssd:
                        moved = "aborted"
                    else:
                        moved = move_data_to_hdd()
                finally:
                
                    with lock:
                        state["transfer_in_progress"] = False

                    save_status()

                if moved is False:
                    with lock:
                        state["pending_transfer"] = False
                        state["last_log"] = "Přesun SSD bufferu dokončen"

                    save_status()

                    print("Přesun dokončen")
                    
                elif moved == "aborted":
                    print("Transfer přerušen kvůli SAFE SWAP")
                    with lock:
                        state["last_log"] = "Transfer přerušen kvůli SAFE SWAP"

                    save_status()
                    
                elif moved is None:

                    print("Chyba transferu SSD -> HDD")

                    with lock:
                        state["last_log"] = "Chyba transferu SSD -> HDD"
                        state["disk_available"] = False

                    save_status()

                    time.sleep(5)
                    
                else:
                    time.sleep(5)
        
            should_save = False
        
            with lock:
                if state["swap_requested"] and not swap_wait_printed:
                    print("SAFE SWAP: čekám na dokončení záznamu")

                    state["last_log"] = "SAFE SWAP: čekám na dokončení záznamu"

                    swap_wait_printed = True
                    should_save = True

            if should_save:
                save_status()

            time.sleep(0.1)

        while True:

            with lock:
                transfer_running = state["transfer_in_progress"]

            if not transfer_running:
                break

            time.sleep(0.1)

        record_once(60, measurement_id)
    
        swap_wait_printed = False
    
        handle_safe_swap()
        
        measurement_id += 1

        next_run += timedelta(minutes=10)

    print("Měření dokončeno.")
    with lock:
        state["last_log"] = "Měření dokončeno"

    save_status()

# ===== CLEANUP =====
finally:
    sdr.deactivateStream(stream)
    sdr.closeStream(stream)
