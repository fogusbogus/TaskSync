import Cocoa
import TaskSync

var url = URLRequest(url: URL(string: "https://localhost:5501/regData/test")!)
url.httpMethod = "GET"
SyncTaskHelper.messageHook = { type, message in
	print("-\(type)-  \(message)")
}
SyncTaskHelper.syncTask(with: url) { data, response, error in
	if let data {
		print(String(data: data, encoding: .utf8)!)
	}
	if let error {
		print(error.localizedDescription)
	}
	if let response {
		print(response)
	}
}
