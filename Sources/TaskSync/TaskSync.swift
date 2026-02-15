import Foundation

/*
 This helper class uses the file system to allow synchronous application of usual async tasks. An id is generated against a task and the file system is used to record the id so it is unique. The synchronisation is done with a wait for the id file to be removed (the file is created with the id creation). In essence this is relying on another processes thread-safeness.
 */

/// Thread-safe task synchroniser
@MainActor public class SyncTaskHelper {
	
	/// The location of the download folder (the folder where we are storing the ids)
	private static var _downloadFolder: String?
	
	/// Get the location of the download folder, creating if required
	public static var downloadFolder: String {
		get {
			guard _downloadFolder == nil else { return _downloadFolder! }
			let folder = FileManager.default.temporaryDirectory
			var sub = UUID().uuidString
			while directoryExistsAtPath(folder.appending(path: sub, directoryHint: .isDirectory)) {
				sub = UUID().uuidString
			}
			let finalPath = folder.appending(path: sub, directoryHint: .isDirectory)
			do {
				//Log.write(message: "Attempting to create folder '\(finalPath.absoluteString)'", type: "I")
				try FileManager.default.createDirectory(at: finalPath, withIntermediateDirectories: true)
				_downloadFolder = finalPath.path
			}
			catch let err {
				//Log.error(err)
				return FileManager.default.temporaryDirectory.absoluteString
			}
			return _downloadFolder!
		}
	}
	
	/// Does a particular directory exist for a given path?
	/// - Parameter path: The full path of the directory
	/// - Returns: true/false
	private static func directoryExistsAtPath(_ path: String) -> Bool {
		var isDirectory : ObjCBool = true
		let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
		return exists && isDirectory.boolValue
	}
	
	/// Does a particular directory exist for a given path?
	/// - Parameter path: The URL path
	/// - Returns: true/false
	private static func directoryExistsAtPath(_ path: URL) -> Bool {
		var isDirectory : ObjCBool = true
		let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
		return exists && isDirectory.boolValue
	}
	
	/// Generates a new ID (and new file) confirming a lock
	private static var newId: UUID {
		get {
			var ret = UUID()
			while hasTask(id: ret) {
				ret = UUID()
			}
			let path = getPath(ret.uuidString)
			//Create the file to reserve
			FileManager.default.createFile(atPath: path, contents: "".data(using: .utf8))
			
			return ret
		}
	}
	
	/// Appends a subpath to the download folder path
	/// - Parameter path: The subpath to add
	/// - Returns: New path
	private static func getPath(_ path: String) -> String {
		return URL(filePath: downloadFolder, directoryHint: .isDirectory).appending(path: path).path
	}
	
	/// Unlocks an id (and deletes the lock file)
	/// - Parameter id: The id to remove
	private static func remove(_ id: UUID) {
		let ids = id.uuidString
		let path = getPath(ids)
		var retry = 10
		while FileManager.default.fileExists(atPath: path) && retry > 0 {
			try? FileManager.default.removeItem(atPath: path)
			retry -= 1
		}
	}
	
	/// Is the task in progress? (i.e. does the file exist?)
	/// - Parameter id: The id of the task
	/// - Returns: True if in progress (file found)
	private static func hasTask(id: UUID) -> Bool {
		return FileManager.default.fileExists(atPath: getPath(id.uuidString))
	}
	
	/// Wait for a process to finish. This is designated as finished if the file doesn't exist (i.e. never there or removed)
	/// - Parameters:
	///   - id: The task id
	///   - process: Post-process callback
	private static func wait(_ id: UUID, _ process: (() -> Bool)? = nil) {
		//If the file doesn't exist, neither does the task in our view
		guard hasTask(id: id) else { return }
		
		//If for some reason the file is removed we need to break out of the loop
		var breakOut = false
		while (!breakOut) {
			//If the file is gone, so is the task
			if !hasTask(id: id) {
				break
			}
			if let process {
				//Do something
				breakOut = process()
			}
		}
		//Make sure the task is removed
		remove(id)
	}
	
	public static func syncTask(with: URL, completion: @Sendable @escaping (Data?, URLResponse?, Error?) -> Void) {
		
		//Get an id for the task (this will create a file)
		let id = newId
		
		//Let's create an async task that we will wait to finish
		let task = URLSession.shared.dataTask(with: with) { data, response, error in
			Task { @MainActor in
				completion(data, response, error)
				//Make sure the task is removed. Duplication elsewhere in the wait? We cater for this, so stop whining.
				remove(id)
			}
		}
		
		//Start it off and wait until it's completed
		task.resume()
		wait(id)
	}
	
	public static func syncTaskWithValue<T: Sendable>(with: URL, defaultValue: T, completion: @Sendable @escaping (Data?, URLResponse?, Error?) -> T) -> T {
		let id = newId
		var ret : T = defaultValue
		let task = URLSession.shared.dataTask(with: with) { data, response, error in
			Task { @MainActor in
				ret = completion(data, response, error)
				remove(id)
			}
		}
		task.resume()
		wait(id)
		return ret
	}
	
	public static func syncTask(with: URLRequest, completion: @Sendable @escaping (Data?, URLResponse?, Error?) -> Void) {
		
		let id = newId
		let task = URLSession.shared.dataTask(with: with) { data, response, error in
			completion(data, response, error)
			Task { @MainActor in
				remove(id)
			}
		}
		task.resume()
		wait(id)
	}
	
	public static func syncTask(with: URL?, timeoutSeconds: Int, completion: @Sendable @escaping (Data?, URLResponse?, Error?) -> Void) {
		guard let with = with else {
			return
		}
		//Log.funcParams("syncTask", items: ["with": with.absoluteString, "timeoutSeconds": timeoutSeconds])
		let id = newId
		let endTS = Date.now.addingTimeInterval(Double(timeoutSeconds))
		let task = URLSession.shared.dataTask(with: with) { data, response, error in
			completion(data, response, error)
			Task { @MainActor in
				remove(id)
			}
		}
		task.resume()
		wait(id) {
			if Date.now > endTS {
				task.cancel()
				return true
			}
			return false
		}
	}
	
	public static func syncTaskWithValue<T: Sendable>(with: URL?, defaultValue: T, timeoutSeconds: Int, completion: @Sendable @escaping (Data?, URLResponse?, Error?) -> T) -> T {
		guard let with = with else {
			return defaultValue
		}
		//Log.funcParams("syncTask", items: ["with": with.absoluteString, "defaultValue":defaultValue, "timeoutSeconds": timeoutSeconds])
		let id = newId
		let endTS = Date.now.addingTimeInterval(Double(timeoutSeconds))
		var ret = defaultValue
		let task = URLSession.shared.dataTask(with: with) { data, response, error in
			Task { @MainActor in
				ret = completion(data, response, error)
				remove(id)
			}
		}
		task.resume()
		wait(id) {
			if Date.now > endTS {
				task.cancel()
				return true
			}
			return false
		}
		return ret
	}
	
	public static func syncTask(with: URLRequest?, timeoutSeconds: Int, completion: @Sendable @escaping (Data?, URLResponse?, Error?) -> Void) {
		guard let with = with else {
			return
		}
		
		let id = newId
		let endTS = Date.now.addingTimeInterval(Double(timeoutSeconds))
		let task = URLSession.shared.uploadTask(with: with, from: with.httpBody) { data, response, error in
			completion(data, response, error)
			Task { @MainActor in
				remove(id)
			}
		}
		task.resume()
		wait(id) {
			if Date.now > endTS {
				task.cancel()
				return true
			}
			return false
		}
	}
}

