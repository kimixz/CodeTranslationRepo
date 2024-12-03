
protocol IStoragePointProvider {
    /**
     *  This method is used for querying storage provider to check if it can provide
     *  usable and reliable data storage places.
     *
     *  @return true if provider can reliably return storage path
     */
    func canProvideStoragePoints() -> Bool

    /**
     *
     * @return available storage points
     */
    func getAvailableStoragePoint() -> [StoragePoint]
}
