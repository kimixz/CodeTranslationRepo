
protocol ConnectivityService {
    func isNetworkAndServerAvailable(callback: @escaping (Bool) -> Void)
    func isConnected() -> Bool
    func isInternetWalled() -> Bool
    func getConnectivity() -> Connectivity

    associatedtype GenericCallback<T>
    func onComplete<T>(_ result: T)
}
