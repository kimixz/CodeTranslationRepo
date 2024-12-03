
import XCTest
import Mockingbird

class RemoteFilesRepositoryTest: XCTestCase {

    var serviceApi: FilesServiceApiMock!
    var mockedReadRemoteFileCallback: FilesRepositoryReadRemoteFileCallbackMock!
    var baseActivity: BaseActivityMock!
    var filesServiceCallbackCaptor: ArgumentCaptor<FilesServiceApi.FilesServiceCallback>!
    var mFilesRepository: FilesRepository!
    var mOCFile: OCFile?

    override func setUp() {
        super.setUp()
        serviceApi = mock(FilesServiceApi.self)
        mockedReadRemoteFileCallback = mock(FilesRepository.ReadRemoteFileCallback.self)
        baseActivity = mock(BaseActivity.self)
        filesServiceCallbackCaptor = ArgumentCaptor<FilesServiceApi.FilesServiceCallback>()
        setUpFilesRepository()
    }

    func setUpFilesRepository() {
        mFilesRepository = RemoteFilesRepository(serviceApi: serviceApi)
    }

    func testReadRemoteFileReturnSuccess() {
        mFilesRepository.readRemoteFile(path: "path", baseActivity: baseActivity, callback: mockedReadRemoteFileCallback)
        verify(serviceApi).readRemoteFile(eq("path"), eq(baseActivity), filesServiceCallbackCaptor.capture())
        filesServiceCallbackCaptor.value?.onLoaded(mOCFile)
        verify(mockedReadRemoteFileCallback).onFileLoaded(eq(mOCFile))
    }

    func testReadRemoteFileReturnError() {
        mFilesRepository.readRemoteFile(path: "path", baseActivity: baseActivity, callback: mockedReadRemoteFileCallback)
        verify(serviceApi).readRemoteFile(eq("path"), eq(baseActivity), filesServiceCallbackCaptor.capture())
        filesServiceCallbackCaptor.value?.onError("error")
        verify(mockedReadRemoteFileCallback).onFileLoadError(eq("error"))
    }
}
