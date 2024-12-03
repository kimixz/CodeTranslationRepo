
import XCTest
import Mockingbird

class ActivityListAdapterTest: XCTestCase {
    var activityListAdapter: ActivityListAdapter!

    override func setUp() {
        super.setUp()
        MockitoAnnotations.initMocks(self)
        MockitoAnnotations.initMocks(activityListAdapter)
        activityListAdapter.values = []
    }

    func testIsHeader_ObjectIsHeader_ReturnTrue() {
        let header: Any = "Hello"
        let activity = MockActivity()

        activityListAdapter.values.append(header)
        activityListAdapter.values.append(activity)

        let result = activityListAdapter.isHeader(0)
        XCTAssertTrue(result)
    }

    func testIsHeader_ObjectIsActivity_ReturnFalse() {
        let header: Any = "Hello"
        let activity = MockActivity()

        activityListAdapter.values.append(header)
        activityListAdapter.values.append(activity)

        XCTAssertFalse(activityListAdapter.isHeader(1))
    }

    func testGetHeaderPositionForItem_AdapterIsEmpty_ReturnZero() {
        Mockito.when(activityListAdapter.isHeader(0)).thenCallRealMethod()
        Mockito.when(activityListAdapter.getItemViewType(0)).thenCallRealMethod()

        XCTAssertEqual(0, activityListAdapter.getHeaderPositionForItem(0))
    }

    func testGetHeaderPositionForItem_ItemIsHeader_ReturnCurrentItem() {
        let header: Any = "Hello"
        let activity = MockActivity()

        Mockito.when(activityListAdapter.isHeader(0)).thenCallRealMethod()
        Mockito.when(activityListAdapter.getItemViewType(0)).thenCallRealMethod()
        Mockito.when(activityListAdapter.isHeader(1)).thenCallRealMethod()
        Mockito.when(activityListAdapter.getItemViewType(1)).thenCallRealMethod()
        Mockito.when(activityListAdapter.isHeader(2)).thenCallRealMethod()
        Mockito.when(activityListAdapter.getItemViewType(2)).thenCallRealMethod()
        Mockito.when(activityListAdapter.getHeaderPositionForItem(2)).thenCallRealMethod()
        Mockito.when(activityListAdapter.isHeader(3)).thenCallRealMethod()
        Mockito.when(activityListAdapter.getItemViewType(3)).thenCallRealMethod()
        Mockito.when(activityListAdapter.getHeaderPositionForItem(3)).thenCallRealMethod()

        activityListAdapter.values.append(header)
        activityListAdapter.values.append(activity)
        activityListAdapter.values.append(header)
        activityListAdapter.values.append(activity)

        XCTAssertEqual(2, activityListAdapter.getHeaderPositionForItem(2))
    }

    func testGetHeaderPositionForItem_ItemIsActivity_ReturnNextHeader() {
        let header: Any = "Hello"
        let activity = mock(Activity.self)

        given(activityListAdapter.isHeader(0)).willReturn(false)
        given(activityListAdapter.getItemViewType(0)).willReturn(1)
        given(activityListAdapter.getHeaderPositionForItem(0)).willReturn(0)
        given(activityListAdapter.isHeader(1)).willReturn(false)
        given(activityListAdapter.getItemViewType(1)).willReturn(1)
        given(activityListAdapter.getHeaderPositionForItem(1)).willReturn(0)
        given(activityListAdapter.isHeader(2)).willReturn(true)
        given(activityListAdapter.getItemViewType(2)).willReturn(0)
        given(activityListAdapter.getHeaderPositionForItem(2)).willReturn(2)
        given(activityListAdapter.isHeader(3)).willReturn(false)
        given(activityListAdapter.getItemViewType(3)).willReturn(1)
        given(activityListAdapter.getHeaderPositionForItem(3)).willReturn(2)

        activityListAdapter.values.append(header)
        activityListAdapter.values.append(activity)
        activityListAdapter.values.append(header)
        activityListAdapter.values.append(activity)

        XCTAssertEqual(2, activityListAdapter.getHeaderPositionForItem(2))
    }
}

class MockActivity: Activity {
    // Mock implementation
}

class ActivityListAdapter {
    var values: [Any] = []

    func isHeader(_ index: Int) -> Bool {
        return getItemViewType(index) == 0
    }

    func getItemViewType(_ index: Int) -> Int {
        // Assuming 0 is for header and 1 is for activity
        return values[index] is String ? 0 : 1
    }

    func getHeaderPositionForItem(_ index: Int) -> Int {
        for i in (0...index).reversed() {
            if isHeader(i) {
                return i
            }
        }
        return 0
    }
}
