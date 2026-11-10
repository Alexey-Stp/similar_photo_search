import DomainTestSupport
import Testing

struct MockLibraryChangeObserverTests {
    @Test func everyStreamReceivesASignal() async {
        let observer = MockLibraryChangeObserver()
        let first = observer.changes()
        let second = observer.changes()
        observer.signal()

        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        let firstSignal: Void? = await firstIterator.next()
        let secondSignal: Void? = await secondIterator.next()
        #expect(firstSignal != nil)
        #expect(secondSignal != nil)
        #expect(observer.changesCallCount == 2)
    }
}
