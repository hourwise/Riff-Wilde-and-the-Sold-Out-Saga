extends Node
## CloudSyncService — Autoload for asynchronous Firebase Realtime Database sync.
## Operates on an offline-first principle: the game is always playable
## without a network connection. Syncs happen in the background and
## failures are silently logged.

signal sync_completed(success: bool)
signal sync_failed(error_message: String)

var _http_request: HTTPRequest
var _pending_requests: int = 0

func _ready() -> void:
	print("[CloudSyncService] Initializing...")
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

## Uploads player progression data to Realtime Database.
## Uses PUT to write the entire user document at /users/{user_id}.json
func upload_player_data(user_id: String, data: Dictionary) -> void:
	if not FirebaseConfig.is_enabled():
		print("[CloudSyncService] Firebase disabled. Skipping upload.")
		return

	var url: String = FirebaseConfig.build_authenticated_url("users/%s" % user_id)
	if url.is_empty():
		push_warning("[CloudSyncService] Invalid RTDB URL. Skipping upload.")
		return

	var headers: PackedStringArray = [
		"Content-Type: application/json"
	]

	var body: String = JSON.stringify(data)
	var error := _http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_warning("[CloudSyncService] HTTP request failed to start: %d" % error)
		sync_failed.emit("Request failed to start (error %d)" % error)
		return

	_pending_requests += 1
	print("[CloudSyncService] Upload queued for user: %s" % user_id)

## Uploads a leaderboard score entry to /leaderboards/{entry_id}.json
func upload_leaderboard_entry(entry: Dictionary) -> void:
	if not FirebaseConfig.is_enabled():
		print("[CloudSyncService] Firebase disabled. Skipping leaderboard upload.")
		return

	var entry_id: String = entry.get("user_id", "unknown") + "_" + str(Time.get_unix_time_from_system())
	var url: String = FirebaseConfig.build_authenticated_url("leaderboards/%s" % entry_id)
	if url.is_empty():
		push_warning("[CloudSyncService] Invalid RTDB URL. Skipping leaderboard upload.")
		return

	var headers: PackedStringArray = [
		"Content-Type: application/json"
	]

	var body: String = JSON.stringify(entry)
	var error := _http_request.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		push_warning("[CloudSyncService] Leaderboard HTTP request failed: %d" % error)
		sync_failed.emit("Leaderboard request failed (error %d)" % error)
		return

	_pending_requests += 1
	print("[CloudSyncService] Leaderboard upload queued: %s" % entry_id)

## Fetches player data from Realtime Database at /users/{user_id}.json
func fetch_player_data(user_id: String) -> void:
	if not FirebaseConfig.is_enabled():
		print("[CloudSyncService] Firebase disabled. Skipping fetch.")
		return

	var url: String = FirebaseConfig.build_authenticated_url("users/%s" % user_id)
	if url.is_empty():
		return

	var headers: PackedStringArray = [
		"Content-Type: application/json"
	]

	var error := _http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		push_warning("[CloudSyncService] Fetch request failed: %d" % error)
		sync_failed.emit("Fetch request failed (error %d)" % error)
		return

	_pending_requests += 1
	print("[CloudSyncService] Fetch queued for user: %s" % user_id)

## Returns the number of in-flight requests.
func has_pending_requests() -> bool:
	return _pending_requests > 0

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending_requests = maxi(0, _pending_requests - 1)

	if result != HTTPRequest.RESULT_SUCCESS:
		var msg: String = "[CloudSyncService] Request failed (result: %d, code: %d)" % [result, response_code]
		push_warning(msg)
		sync_failed.emit(msg)
		return

	if response_code >= 200 and response_code < 300:
		print("[CloudSyncService] Request succeeded (HTTP %d)" % response_code)
		sync_completed.emit(true)
	else:
		var response_body: String = body.get_string_from_utf8()
		var msg: String = "[CloudSyncService] Request returned HTTP %d: %s" % [response_code, response_body]
		push_warning(msg)
		sync_failed.emit(msg)
