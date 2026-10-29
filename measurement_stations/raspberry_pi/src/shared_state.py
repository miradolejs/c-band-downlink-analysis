from threading import Lock

state = {
    "use_ssd": False,
    "disk_available": True,
    "transfer_in_progress": False,
    "safe_to_remove": False,
    "current_dir": "",
    "last_log": "",
	"idle": True,
	"swap_requested": False,
	"force_ssd": False,
	"pending_transfer": False,
	
}

lock = Lock()
