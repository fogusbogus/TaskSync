import Cocoa

var url = URLRequest(url: URL(string: "https://localhost:5501/regData/test")!)
url.httpMethod = "GET"
SyncTaskHelper.syncTask(with: url) { data, response, error in
	print(String(data: data, encoding: .utf8))
}
