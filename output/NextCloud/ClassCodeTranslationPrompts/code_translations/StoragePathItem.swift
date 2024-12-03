
class StoragePathItem {
    private var icon: Int
    private var name: String
    private var path: String

    init(icon: Int, name: String, path: String) {
        self.icon = icon
        self.name = name
        self.path = path
    }

    func getIcon() -> Int {
        return self.icon
    }

    func getName() -> String {
        return self.name
    }

    func getPath() -> String {
        return self.path
    }

    func setIcon(_ icon: Int) {
        self.icon = icon
    }

    func setName(_ name: String) {
        self.name = name
    }

    func setPath(_ path: String) {
        self.path = path
    }
}
