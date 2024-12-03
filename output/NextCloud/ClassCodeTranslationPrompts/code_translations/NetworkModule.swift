
import Foundation
import SystemConfiguration

class NetworkModule {

    func connectivityService(connectivityManager: ConnectivityManager, 
                             accountManager: UserAccountManager, 
                             clientFactory: ClientFactory, 
                             walledCheckCache: WalledCheckCache) -> ConnectivityService {
        return ConnectivityServiceImpl(connectivityManager: connectivityManager, 
                                       accountManager: accountManager, 
                                       clientFactory: clientFactory, 
                                       getRequestBuilder: ConnectivityServiceImpl.GetRequestBuilder(), 
                                       walledCheckCache: walledCheckCache)
    }

    func clientFactory(context: Context) -> ClientFactory {
        return ClientFactoryImpl(context: context)
    }

    func connectivityManager(context: Context) -> ConnectivityManager? {
        return context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    }
}
