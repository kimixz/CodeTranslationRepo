
import Foundation

class ProcessVEvent {
    private static let TAG = "ICS_ProcessVEvent"
    
    private static let ONE_DAY = createDuration(value: "P1D")
    private static let ZERO_SECONDS = createDuration(value: "PT0S")
    
    private static let EVENT_QUERY_COLUMNS = [Events.CALENDAR_ID, Events._ID]
    private static let EVENT_QUERY_CALENDAR_ID_COL = 0
    private static let EVENT_QUERY_ID_COL = 1
    
    private let mICalCalendar: Calendar
    private let mIsInserter: Bool
    private let selectedCal: AndroidCalendar
    
    private var context: Context
    
    @Inject var preferences: AppPreferences
    
    // UID generation
    var mUidMs: Int64 = 0
    var mUidTail: String? = nil
    
    private class Options {
        private let mDefaultReminders: [Int]
        
        init(context: Context) {
            mDefaultReminders = [0, 5, 10, 30, 60]
        }
        
        func getReminders(eventReminders: [Int]) -> [Int] {
            if eventReminders.count > 0 && getImportReminders() {
                return eventReminders
            }
            return mDefaultReminders
        }
        
        func getKeepUids() -> Bool {
            return true
        }
        
        private func getImportReminders() -> Bool {
            return true
        }
        
        private func getGlobalUids() -> Bool {
            return false
        }
        
        private func getTestFileSupport() -> Bool {
            return false
        }
        
        func getDuplicateHandling() -> DuplicateHandlingEnum {
            return DuplicateHandlingEnum.allCases[0]
        }
    }
    
    init(context: Context, iCalCalendar: Calendar, selectedCal: AndroidCalendar, isInserter: Bool) {
        self.context = context
        self.mICalCalendar = iCalCalendar
        self.selectedCal = selectedCal
        self.mIsInserter = isInserter
    }
    
    func run() throws {
        let options = Options(context: context)
        var reminders: [Int] = []
        
        let events = mICalCalendar.getComponents(VEvent.VEVENT)
        
        let resolver = context.contentResolver
        var numDel = 0
        var numIns = 0
        var numDups = 0
        
        var cAlarm = ContentValues()
        cAlarm.put(Reminders.METHOD, Reminders.METHOD_ALERT)
        
        let dupes = options.getDuplicateHandling()
        
        Log_OC.i(TAG, "\(mIsInserter ? "Insert" : "Delete") for id \(selectedCal.mIdStr)")
        Log_OC.d(TAG, "Duplication option is \(dupes.rawValue)")
        
        for ve in events {
            guard let e = ve as? VEvent else { continue }
            Log_OC.d(TAG, "source event: \(e)")
            
            if e.getRecurrenceId() != nil {
                Log_OC.w(TAG, "Ignoring edited instance of a recurring event")
                continue
            }
            
            var insertCalendarId = selectedCal.mId
            
            let c = convertToDB(e: e, options: options, reminders: &reminders, calendarId: selectedCal.mId)
            
            var cur: Cursor? = nil
            var mustDelete = !mIsInserter
            
            if !mustDelete && dupes != .DUP_DONT_CHECK {
                cur = query(resolver: resolver, options: options, c: c)
                while !mustDelete && cur != nil && cur!.moveToNext() {
                    if dupes == .DUP_REPLACE {
                        mustDelete = cur!.getLong(EVENT_QUERY_CALENDAR_ID_COL) == selectedCal.mId
                    } else {
                        mustDelete = true
                    }
                }
                
                if mustDelete {
                    if dupes == .DUP_IGNORE {
                        Log_OC.i(TAG, "Avoiding inserting a duplicate event")
                        numDups += 1
                        cur?.close()
                        continue
                    }
                    cur?.moveToPosition(-1)
                }
            }
            
            if mustDelete {
                if cur == nil {
                    cur = query(resolver: resolver, options: options, c: c)
                }
                
                while cur != nil && cur!.moveToNext() {
                    let rowCalendarId = cur!.getLong(EVENT_QUERY_CALENDAR_ID_COL)
                    
                    if dupes == .DUP_REPLACE && rowCalendarId != selectedCal.mId {
                        Log_OC.i(TAG, "Avoiding deleting duplicate event in calendar \(rowCalendarId)")
                        continue
                    }
                    
                    let id = cur!.getString(EVENT_QUERY_ID_COL)
                    let eventUri = Uri.withAppendedPath(Events.CONTENT_URI, id)
                    numDel += resolver.delete(eventUri, null, null)
                    let whereClause = "\(Reminders.EVENT_ID)=?"
                    resolver.delete(Reminders.CONTENT_URI, whereClause, [id])
                    if mIsInserter && rowCalendarId != selectedCal.mId && dupes == .DUP_REPLACE_ANY {
                        Log_OC.i(TAG, "Changing calendar: \(rowCalendarId) to \(insertCalendarId)")
                        insertCalendarId = rowCalendarId
                    }
                }
            }
            
            cur?.close()
            
            if !mIsInserter {
                continue
            }
            
            if Events.UID_2445 != nil && !c.containsKey(Events.UID_2445) {
                c.put(Events.UID_2445, generateUid())
            }
            
            c.put(Events.CALENDAR_ID, insertCalendarId)
            if options.getTestFileSupport() {
                processEventTests(e: e, c: &c, reminders: reminders)
                numIns += 1
                continue
            }
            
            let uri = insertAndLog(resolver: resolver, uri: Events.CONTENT_URI, values: c, type: "Event")
            if uri == nil {
                continue
            }
            
            let id = Int64(uri!.lastPathSegment!)!
            
            for time in options.getReminders(eventReminders: reminders) {
                cAlarm.put(Reminders.EVENT_ID, id)
                cAlarm.put(Reminders.MINUTES, time)
                insertAndLog(resolver: resolver, uri: Reminders.CONTENT_URI, values: cAlarm, type: "Reminder")
            }
            numIns += 1
        }
        
        selectedCal.mNumEntries += numIns
        selectedCal.mNumEntries -= numDel
        
        let res = context.resources
        let n = mIsInserter ? numIns : numDel
        var msg = res.getQuantityString(R.plurals.processed_n_entries, n, n) + "\n"
        if mIsInserter {
            msg += "\n"
            if options.getDuplicateHandling() == .DUP_DONT_CHECK {
                msg += res.getString(R.string.did_not_check_for_dupes)
            } else {
                msg += res.getQuantityString(R.plurals.found_n_duplicates, numDups, numDups)
            }
        }
    }
    
    private func convertToDB(e: VEvent, options: Options, reminders: inout [Int], calendarId: Int64) -> [String: Any] {
        reminders.removeAll()
        
        var allDay = false
        let startIsDate = !(e.startDate.date is DateTime)
        let isRecurring = hasProperty(e: e, name: Property.RRULE) || hasProperty(e: e, name: Property.RDATE)
        
        if startIsDate {
            allDay = true
        }
        
        if !hasProperty(e: e, name: Property.DTEND) && !hasProperty(e: e, name: Property.DURATION) {
            e.properties.append(ZERO_SECONDS)
            removeProperty(from: e, name: Property.TRANSP)
            e.properties.append(Transp.TRANSPARENT)
        }
        
        if isRecurring {
            if !hasProperty(e: e, name: Property.DURATION) {
                let d = Duration(start: e.startDate.date, end: e.endDate.date)
                e.properties.append(d)
            }
            removeProperty(from: e, name: Property.DTEND)
        } else {
            if !hasProperty(e: e, name: Property.DTEND) {
                e.properties.append(e.endDate)
            }
            removeProperty(from: e, name: Property.DURATION)
        }
        
        var c = [String: Any]()
        
        c[Events.CALENDAR_ID] = calendarId
        copyProperty(c: &c, dbName: Events.TITLE, e: e, evName: Property.SUMMARY)
        copyProperty(c: &c, dbName: Events.DESCRIPTION, e: e, evName: Property.DESCRIPTION)
        
        if let organizer = e.organizer {
            let uri = organizer.calAddress
            do {
                let mailTo = try MailTo.parse(uri: uri.absoluteString)
                c[Events.ORGANIZER] = mailTo.to
                c[Events.GUESTS_CAN_MODIFY] = 1
            } catch {
                print("Failed to parse Organiser URI \(uri.absoluteString)")
            }
        }
        
        copyProperty(c: &c, dbName: Events.EVENT_LOCATION, e: e, evName: Property.LOCATION)
        
        if hasProperty(e: e, name: Property.STATUS) {
            let status = e.getProperty(name: Property.STATUS)?.value
            switch status {
            case "TENTATIVE":
                c[Events.STATUS] = Events.STATUS_TENTATIVE
            case "CONFIRMED":
                c[Events.STATUS] = Events.STATUS_CONFIRMED
            case "CANCELLED":
                c[Events.STATUS] = Events.STATUS_CANCELED
            default:
                break
            }
        }
        
        copyProperty(c: &c, dbName: Events.DURATION, e: e, evName: Property.DURATION)
        
        if allDay {
            c[Events.ALL_DAY] = 1
        }
        
        copyDateProperty(c: &c, dbName: Events.DTSTART, dbTzName: Events.EVENT_TIMEZONE, date: e.startDate)
        if hasProperty(e: e, name: Property.DTEND) {
            copyDateProperty(c: &c, dbName: Events.DTEND, dbTzName: Events.EVENT_END_TIMEZONE, date: e.endDate)
        }
        
        if hasProperty(e: e, name: Property.CLASS) {
            let access = e.getProperty(name: Property.CLASS)?.value
            var accessLevel = Events.ACCESS_DEFAULT
            switch access {
            case "CONFIDENTIAL":
                accessLevel = Events.ACCESS_CONFIDENTIAL
            case "PRIVATE":
                accessLevel = Events.ACCESS_PRIVATE
            case "PUBLIC":
                accessLevel = Events.ACCESS_PUBLIC
            default:
                break
            }
            c[Events.ACCESS_LEVEL] = accessLevel
        }
        
        if Events.AVAILABILITY != nil {
            var availability = Events.AVAILABILITY_BUSY
            if hasProperty(e: e, name: Property.TRANSP) {
                if e.transparency == Transp.TRANSPARENT {
                    availability = Events.AVAILABILITY_FREE
                }
            } else if hasProperty(e: e, name: Property.FREEBUSY) {
                if let fb = e.getProperty(name: Property.FREEBUSY) as? FreeBusy,
                   let fbType = fb.getParameter(parameter: Parameter.FBTYPE) as? FbType {
                    if fbType == .FREE {
                        availability = Events.AVAILABILITY_FREE
                    } else if fbType == .BUSY_TENTATIVE {
                        availability = Events.AVAILABILITY_TENTATIVE
                    }
                }
            }
            c[Events.AVAILABILITY] = availability
        }
        
        copyProperty(c: &c, dbName: Events.RRULE, e: e, evName: Property.RRULE)
        copyProperty(c: &c, dbName: Events.RDATE, e: e, evName: Property.RDATE)
        copyProperty(c: &c, dbName: Events.EXRULE, e: e, evName: Property.EXRULE)
        copyProperty(c: &c, dbName: Events.EXDATE, e: e, evName: Property.EXDATE)
        copyProperty(c: &c, dbName: Events.CUSTOM_APP_URI, e: e, evName: Property.URL)
        copyProperty(c: &c, dbName: Events.UID_2445, e: e, evName: Property.UID)
        if let uid = c[Events.UID_2445] as? String, uid.isEmpty {
            c.removeValue(forKey: Events.UID_2445)
        }
        
        for alarm in e.alarms {
            guard let a = alarm as? VAlarm else { continue }
            
            if a.action != .AUDIO && a.action != .DISPLAY {
                continue
            }
            
            let t = a.trigger
            let startMs = e.startDate.date.timeIntervalSince1970 * 1000
            var alarmStartMs = startMs
            var alarmMs: TimeInterval
            
            if let dateTime = t.dateTime {
                alarmMs = dateTime.timeIntervalSince1970 * 1000
            } else if let duration = t.duration, duration.isNegative {
                if let rel = t.getParameter(parameter: Parameter.RELATED) as? Related, rel == .END {
                    alarmStartMs = e.endDate.date.timeIntervalSince1970 * 1000
                }
                alarmMs = alarmStartMs - durationToMs(d: duration)
            } else if let duration = t.duration, !duration.isNegative {
                if let rel = t.getParameter(parameter: Parameter.RELATED) as? Related, rel == .END {
                    alarmStartMs = e.endDate.date.timeIntervalSince1970 * 1000
                }
                alarmMs = alarmStartMs + durationToMs(d: duration)
            } else {
                continue
            }
            
            let reminder = Int((startMs - alarmMs) / DateUtils.MINUTE_IN_MILLIS)
            if !reminders.contains(reminder) {
                reminders.append(reminder)
            }
        }
        
        if options.getReminders(eventReminders: reminders).count > 0 {
            c[Events.HAS_ALARM] = 1
        }
        
        return c
    }
    
    private static func createDuration(value: String) -> Duration {
        let d = Duration()
        d.setValue(value)
        return d
    }
    
    private static func durationToMs(d: Dur) -> Int64 {
        var ms: Int64 = 0
        ms += Int64(d.getSeconds()) * DateUtils.SECOND_IN_MILLIS
        ms += Int64(d.getMinutes()) * DateUtils.MINUTE_IN_MILLIS
        ms += Int64(d.getHours()) * DateUtils.HOUR_IN_MILLIS
        ms += Int64(d.getDays()) * DateUtils.DAY_IN_MILLIS
        ms += Int64(d.getWeeks()) * DateUtils.WEEK_IN_MILLIS
        return ms
    }
    
    private func hasProperty(e: VEvent, name: String) -> Bool {
        return e.getProperty(name: name) != nil
    }
    
    private func removeProperty(from event: VEvent, name: String) {
        if let property = event.getProperty(name: name) {
            event.getProperties().remove(property)
        }
    }
    
    private func copyProperty(c: inout [String: Any], dbName: String?, e: VEvent, evName: String) {
        if let dbName = dbName {
            if let p = e.getProperty(name: evName) {
                c[dbName] = p.getValue()
            }
        }
    }
    
    private func copyDateProperty(c: inout [String: Any], dbName: String?, dbTzName: String?, date: DateProperty) {
        if let dbName = dbName, let dateValue = date.getDate() {
            c[dbName] = dateValue.timeIntervalSince1970 * 1000
            if let dbTzName = dbTzName {
                if date.isUtc() || date.getTimeZone() == nil {
                    c[dbTzName] = "UTC"
                } else {
                    c[dbTzName] = date.getTimeZone()?.identifier
                }
            }
        }
    }
    
    private func insertAndLog(resolver: ContentResolver, uri: Uri, values: ContentValues, type: String) -> Uri? {
        Log_OC.d(TAG, "Inserting \(type) values: \(values)")
        
        let result = resolver.insert(uri, values)
        if result == nil {
            Log_OC.e(TAG, "failed to insert \(type)")
            Log_OC.e(TAG, "failed \(type) values: \(values)")
        } else {
            Log_OC.d(TAG, "Insert \(type) returned \(result!.toString())")
        }
        return result
    }
    
    private func queryEvents(resolver: ContentResolver, b: StringBuilder, argsList: [String]) -> Cursor? {
        let whereClause = "\(b.toString()) AND deleted=0"
        let args = argsList.map { $0 }
        return resolver.query(Events.CONTENT_URI, EVENT_QUERY_COLUMNS, whereClause, args, nil)
    }
    
    private func query(resolver: ContentResolver, options: Options, c: ContentValues) -> Cursor? {
        var b = StringBuilder()
        var argsList = [String]()
        
        if options.getKeepUids() && Events.UID_2445 != nil && c.containsKey(Events.UID_2445) {
            if !options.getGlobalUids() {
                b.append("\(Events.CALENDAR_ID)=? AND ")
                argsList.append(c.getAsString(Events.CALENDAR_ID))
            }
            b.append("\(Events.UID_2445)=?")
            argsList.append(c.getAsString(Events.UID_2445))
            return queryEvents(resolver: resolver, b: b, argsList: argsList)
        }
        
        if !c.containsKey(Events.CALENDAR_ID) || !c.containsKey(Events.DTSTART) {
            return nil
        }
        
        b.append("\(Events.CALENDAR_ID)=? AND ")
        b.append("\(Events.DTSTART)=? AND ")
        b.append(Events.TITLE)
        
        argsList.append(c.getAsString(Events.CALENDAR_ID))
        argsList.append(c.getAsString(Events.DTSTART))
        
        if c.containsKey(Events.TITLE) {
            b.append("=?")
            argsList.append(c.getAsString(Events.TITLE))
        } else {
            b.append(" is null")
        }
        
        return queryEvents(resolver: resolver, b: b, argsList: argsList)
    }
    
    private func checkTestValue(e: VEvent, c: [String: Any], keyValue: String, testName: String) {
        let parts = keyValue.split(separator: "=")
        let key = String(parts[0])
        let expected = parts.count > 1 ? String(parts[1]) : ""
        var got = c[key] as? String
        
        if expected == "<non-null>" && got != nil {
            got = "<non-null>"
        }
        if got == nil {
            got = "<null>"
        }
        
        if expected != got {
            Log_OC.e(TAG, "    \(keyValue) -> FAILED")
            Log_OC.e(TAG, "    values: \(c)")
            let error = "Test \(testName) FAILED, expected '\(keyValue)', got '\(got ?? "<null>")'"
            fatalError(error)
        }
        Log_OC.i(TAG, "    \(keyValue) -> PASSED")
    }
    
    private func processEventTests(e: VEvent, c: inout [String: Any], reminders: [Int]) {
        guard let testName = e.getProperty(name: "X-TEST-NAME") else {
            return
        }
        
        Log_OC.i(TAG, "Processing test case \(testName.getValue())...")
        
        var reminderValues = ""
        var sep = ""
        for i in reminders {
            reminderValues += sep + String(i)
            sep = ","
        }
        c["reminders"] = reminderValues
        
        for o in e.getProperties() {
            if let p = o as? Property {
                switch p.getName() {
                case "X-TEST-VALUE":
                    checkTestValue(e: e, c: &c, keyValue: p.getValue(), testName: testName.getValue())
                case "X-TEST-MIN-VERSION":
                    if let ver = Int(p.getValue()), android.os.Build.VERSION.SDK_INT < ver {
                        Log_OC.e(TAG, "    -> SKIPPED (MIN-VERSION < \(ver))")
                        return
                    }
                default:
                    break
                }
            }
        }
    }
    
    private func generateUid() -> String {
        if mUidTail == nil {
            var uidPid = preferences.getUidPid()
            if uidPid.isEmpty {
                uidPid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                preferences.setUidPid(uidPid)
            }
            mUidTail = uidPid + "@nextcloud.com"
        }
        
        mUidMs = max(mUidMs, Date().timeIntervalSince1970 * 1000)
        let uid = "\(Int(mUidMs))\(mUidTail!)"
        mUidMs += 1
        
        return uid
    }
}
