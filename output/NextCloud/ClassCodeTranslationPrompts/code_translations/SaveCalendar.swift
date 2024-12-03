
import Foundation
import UIKit

class SaveCalendar {
    private static let TAG = "ICS_SaveCalendar"
    
    private let mPropertyFactory = PropertyFactoryRegistry()
    private var mTzRegistry: TimeZoneRegistry?
    private var mInsertedTimeZones = Set<TimeZone>()
    private var mFailedOrganisers = Set<String>()
    private var mAllCols = false
    private let activity: Context
    private let selectedCal: AndroidCalendar
    private let preferences: AppPreferences
    private let user: User
    
    // UID generation
    private var mUidMs: Int64 = 0
    private var mUidTail: String?
    
    private static let STATUS_ENUM = ["TENTATIVE", "CONFIRMED", "CANCELLED"]
    private static let CLASS_ENUM = [nil, "CONFIDENTIAL", "PRIVATE", "PUBLIC"]
    private static let AVAIL_ENUM = [nil, "FREE", "BUSY-TENTATIVE"]
    
    private static let EVENT_COLS = [
        Events._ID, Events.ORIGINAL_ID, Events.UID_2445, Events.TITLE, Events.DESCRIPTION,
        Events.ORGANIZER, Events.EVENT_LOCATION, Events.STATUS, Events.ALL_DAY, Events.RDATE,
        Events.RRULE, Events.DTSTART, Events.EVENT_TIMEZONE, Events.DURATION, Events.DTEND,
        Events.EVENT_END_TIMEZONE, Events.ACCESS_LEVEL, Events.AVAILABILITY, Events.EXDATE,
        Events.EXRULE, Events.CUSTOM_APP_PACKAGE, Events.CUSTOM_APP_URI, Events.HAS_ALARM
    ]
    
    private static let REMINDER_COLS = [
        Reminders.MINUTES, Reminders.METHOD
    ]
    
    init(activity: Context, calendar: AndroidCalendar, preferences: AppPreferences, user: User) {
        self.activity = activity
        self.selectedCal = calendar
        self.preferences = preferences
        self.user = user
    }
    
    func start() throws {
        mInsertedTimeZones.removeAll()
        mFailedOrganisers.removeAll()
        mAllCols = false
        
        let file = "\(selectedCal.mDisplayName)_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)).ics"
        let fileName = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        
        print("Save id \(selectedCal.mIdStr) to file \(fileName.path)")
        
        let name = Bundle.main.bundleIdentifier ?? "Unknown"
        var ver: String
        do {
            let info = try Bundle.main.infoDictionary
            ver = info?["CFBundleShortVersionString"] as? String ?? "Unknown Build"
        } catch {
            ver = "Unknown Build"
        }
        
        let prodId = "-//\(selectedCal.mOwner)//iCal Import/Export \(ver)//EN"
        let cal = Calendar()
        cal.properties.append(ProdId(prodId))
        cal.properties.append(Version.VERSION_2_0)
        cal.properties.append(Method.PUBLISH)
        cal.properties.append(CalScale.GREGORIAN)
        
        if let timezone = selectedCal.mTimezone {
            cal.properties.append(XProperty("X-WR-TIMEZONE", timezone))
        }
        
        let resolver = activity.contentResolver
        var numberOfCreatedUids = 0
        if Events.UID_2445 != nil {
            numberOfCreatedUids = ensureUids(activity: activity, resolver: resolver, cal: selectedCal)
        }
        let relaxed = true
        CompatibilityHints.setHintEnabled(CompatibilityHints.KEY_RELAXED_VALIDATION, relaxed)
        let events = getEvents(resolver: resolver, cal_src: selectedCal, cal_dst: cal)
        
        for v in events {
            cal.components.append(v)
        }
        
        if !cal.components.isEmpty {
            try CalendarOutputter().output(cal, to: FileOutputStream(fileName))
            
            let res = activity.resources
            var msg = res.getQuantityString(R.plurals.wrote_n_events_to, events.count, events.count, file)
            if numberOfCreatedUids > 0 {
                msg += "\n" + res.getQuantityString(R.plurals.created_n_uids_to, numberOfCreatedUids, numberOfCreatedUids)
            }
            
            // TODO replace DisplayUtils.showSnackMessage(activity, msg)
            
            upload(file: fileName)
        } else {
            print("Calendar '\(selectedCal.mIdStr)' has no components")
        }
    }
    
    private func ensureUids(activity: Context, resolver: ContentResolver, cal: AndroidCalendar) -> Int {
        let cols = [Events._ID]
        let args = [cal.mIdStr]
        var newUids = [Int64: String]()
        let cur = resolver.query(Events.CONTENT_URI, cols, "\(Events.CALENDAR_ID) = ? AND \(Events.UID_2445) IS NULL", args, nil)
        
        while cur?.moveToNext() == true {
            if let id = getLong(cur, dbName: Events._ID) {
                let uid = generateUid()
                newUids[id] = uid
            }
        }
        
        for (id, uid) in newUids {
            let updateUri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id)
            var c = ContentValues()
            c.put(Events.UID_2445, uid)
            resolver.update(updateUri, c, nil, nil)
            Log_OC.i(SaveCalendar.TAG, "Generated UID \(uid) for event \(id)")
        }
        
        return newUids.count
    }
    
    private func getEvents(resolver: ContentResolver, cal_src: AndroidCalendar, cal_dst: Calendar) -> [VEvent] {
        let whereClause = "\(Events.CALENDAR_ID)=?"
        let args = [cal_src.mIdStr]
        let sortBy = "\(Events.CALENDAR_ID) ASC"
        var cur: Cursor?
        do {
            cur = try resolver.query(Events.CONTENT_URI, mAllCols ? nil : SaveCalendar.EVENT_COLS, whereClause, args, sortBy)
        } catch {
            Log_OC.w(SaveCalendar.TAG, "Calendar provider is missing columns, continuing anyway")
            for n in 0..<SaveCalendar.EVENT_COLS.count {
                if SaveCalendar.EVENT_COLS[n] == nil {
                    Log_OC.e(SaveCalendar.TAG, "Invalid EVENT_COLS index \(n)")
                }
            }
            cur = try? resolver.query(Events.CONTENT_URI, nil, whereClause, args, sortBy)
        }
        
        let timestamp = DtStamp() // Same timestamp for all events
        
        // Collect up events and add them after any timezones
        var events = [VEvent]()
        while cur?.moveToNext() == true {
            if let e = convertFromDb(cur: cur!, cal: cal_dst, timestamp: timestamp) {
                events.append(e)
                Log_OC.d(SaveCalendar.TAG, "Adding event: \(e)")
            }
        }
        cur?.close()
        return events
    }
    
    private func calculateFileName(_ displayName: String) -> String {
        let stripped = displayName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
        return stripped.replacingOccurrences(of: "(_){2,}", with: "_", options: .regularExpression)
    }
    
    private func getFileImpl(previousFile: String, suggestedFile: String, result: inout [String]) {
        let input = UITextField()
        input.placeholder = NSLocalizedString("destination_filename", comment: "")
        input.text = previousFile
        input.selectAll(nil)
        
        let alert = UIAlertController(title: NSLocalizedString("enter_destination_filename", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = previousFile
        }
        
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            if let text = alert.textFields?.first?.text {
                result[0] = text
            }
        }
        
        let suggestAction = UIAlertAction(title: NSLocalizedString("suggest", comment: ""), style: .default) { _ in
            if let textField = alert.textFields?.first {
                textField.text = suggestedFile
                textField.selectAll(nil)
            }
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            result[0] = ""
        }
        
        alert.addAction(okAction)
        alert.addAction(suggestAction)
        alert.addAction(cancelAction)
        
        if let viewController = UIApplication.shared.keyWindow?.rootViewController {
            viewController.present(alert, animated: true) {
                alert.textFields?.first?.becomeFirstResponder()
            }
        }
    }
    
    private func convertFromDb(cur: Cursor, cal: Calendar, timestamp: DtStamp) -> VEvent? {
        Log_OC.d(SaveCalendar.TAG, "cursor: \(DatabaseUtils.dumpCurrentRowToString(cur))")
        
        if hasStringValue(cur: cur, dbName: Events.ORIGINAL_ID) {
            Log_OC.w(SaveCalendar.TAG, "Ignoring edited instance of a recurring event")
            return nil
        }
        
        var l = PropertyList()
        l.add(timestamp)
        copyProperty(l: &l, eventName: Property.UID, cursor: cur, dbName: Events.UID_2445)
        
        let summary = copyProperty(l: &l, eventName: Property.SUMMARY, cursor: cur, dbName: Events.TITLE)
        let description = copyProperty(l: &l, eventName: Property.DESCRIPTION, cursor: cur, dbName: Events.DESCRIPTION)
        
        var organizer = getString(cur: cur, dbName: Events.ORGANIZER)
        if !TextUtils.isEmpty(organizer) {
            if !organizer.starts(with: "mailto:") {
                organizer = "mailto:" + organizer
            }
            do {
                try l.add(Organizer(organizer))
            } catch {
                if !mFailedOrganisers.contains(organizer) {
                    Log_OC.e(SaveCalendar.TAG, "Failed to create mailTo for organizer \(organizer)")
                    mFailedOrganisers.insert(organizer)
                }
            }
        }
        
        copyProperty(l: &l, eventName: Property.LOCATION, cursor: cur, dbName: Events.EVENT_LOCATION)
        copyEnumProperty(l: &l, evName: Property.STATUS, cur: cur, dbName: Events.STATUS, vals: SaveCalendar.STATUS_ENUM)
        
        let allDay = TextUtils.equals(getString(cur: cur, dbName: Events.ALL_DAY), "1")
        var isTransparent: Bool
        var dtEnd: DtEnd? = nil
        
        if allDay {
            isTransparent = true
            let start = getDateTime(cur: cur, dbName: Events.DTSTART, dbTzName: nil, cal: nil)
            let end = getDateTime(cur: cur, dbName: Events.DTEND, dbTzName: nil, cal: nil)
            l.add(DtStart(Date(start!)))
            
            if let end = end {
                dtEnd = DtEnd(Date(end))
            } else {
                dtEnd = DtEnd(utcDateFromMs(start!.timeIntervalSince1970 + DateUtils.DAY_IN_MILLIS))
            }
            
            l.add(dtEnd!)
        } else {
            let startDate = getDateTime(cur: cur, dbName: Events.DTSTART, dbTzName: Events.EVENT_TIMEZONE, cal: cal)
            l.add(DtStart(startDate!))
            
            if hasStringValue(cur: cur, dbName: Events.DURATION) {
                isTransparent = getString(cur: cur, dbName: Events.DURATION) == "PT0S"
                if !isTransparent {
                    copyProperty(l: &l, eventName: Property.DURATION, cursor: cur, dbName: Events.DURATION)
                }
            } else {
                var endTz = Events.EVENT_END_TIMEZONE
                if endTz == nil {
                    endTz = Events.EVENT_TIMEZONE
                }
                let end = getDateTime(cur: cur, dbName: Events.DTEND, dbTzName: endTz, cal: cal)
                dtEnd = DtEnd(end!)
                isTransparent = startDate!.timeIntervalSince1970 == end!.timeIntervalSince1970
                if !isTransparent {
                    l.add(dtEnd!)
                }
            }
        }
        
        copyEnumProperty(l: &l, evName: Property.CLASS, cur: cur, dbName: Events.ACCESS_LEVEL, vals: SaveCalendar.CLASS_ENUM)
        
        var availability = getInt(cur: cur, dbName: Events.AVAILABILITY)
        if availability > Events.AVAILABILITY_TENTATIVE {
            availability = -1
        }
        
        if isTransparent {
            if availability >= 0 && availability != Events.AVAILABILITY_FREE {
                l.add(Transp.OPAQUE)
            }
        } else if availability > Events.AVAILABILITY_BUSY {
            let fb = FreeBusy()
            fb.getParameters().add(FbType(SaveCalendar.AVAIL_ENUM[availability]!))
            let start = DateTime(((l.getProperty(Property.DTSTART) as! DtStart).date))
            
            if let dtEnd = dtEnd {
                fb.getPeriods().add(Period(start, DateTime(dtEnd.date)))
            } else {
                let d = l.getProperty(Property.DURATION) as! Duration
                fb.getPeriods().add(Period(start, d.duration))
            }
            l.add(fb)
        }
        
        copyProperty(l: &l, eventName: Property.RRULE, cursor: cur, dbName: Events.RRULE)
        copyProperty(l: &l, eventName: Property.RDATE, cursor: cur, dbName: Events.RDATE)
        copyProperty(l: &l, eventName: Property.EXRULE, cursor: cur, dbName: Events.EXRULE)
        copyProperty(l: &l, eventName: Property.EXDATE, cursor: cur, dbName: Events.EXDATE)
        if TextUtils.isEmpty(getString(cur: cur, dbName: Events.CUSTOM_APP_PACKAGE)) {
            copyProperty(l: &l, eventName: Property.URL, cursor: cur, dbName: Events.CUSTOM_APP_URI)
        }
        
        let e = VEvent(l)
        
        if getInt(cur: cur, dbName: Events.HAS_ALARM) == 1 {
            let s = summary ?? (description ?? "")
            let desc = Description(s)
            
            let resolver = activity.contentResolver
            let eventId = getLong(cur: cur, dbName: Events._ID)
            let alarmCur = Reminders.query(resolver, eventId: eventId, projection: mAllCols ? nil : SaveCalendar.REMINDER_COLS)
            while alarmCur.moveToNext() {
                var mins = getInt(alarmCur, dbName: Reminders.MINUTES)
                if mins == -1 {
                    mins = 60
                }
                
                let method = getInt(alarmCur, dbName: Reminders.METHOD)
                if method == Reminders.METHOD_DEFAULT || method == Reminders.METHOD_ALERT {
                    let alarm = VAlarm(Dur(0, 0, -mins, 0))
                    alarm.getProperties().add(Action.DISPLAY)
                    alarm.getProperties().add(desc)
                    e.getAlarms().add(alarm)
                }
            }
            alarmCur.close()
        }
        
        return e
    }
    
    private func getColumnIndex(cur: Cursor, dbName: String?) -> Int {
        return dbName == nil ? -1 : cur.getColumnIndexOrThrow(dbName!)
    }
    
    private func getString(cur: Cursor, dbName: String) -> String? {
        let i = getColumnIndex(cur: cur, dbName: dbName)
        return i == -1 ? nil : cur.getString(i)
    }
    
    private func getLong(cur: Cursor, dbName: String) -> Int64 {
        let i = getColumnIndex(cur: cur, dbName: dbName)
        return i == -1 ? -1 : cur.getLong(i)
    }
    
    private func getInt(cur: Cursor, dbName: String) -> Int {
        let i = getColumnIndex(cur: cur, dbName: dbName)
        return i == -1 ? -1 : cur.getInt(i)
    }
    
    private func hasStringValue(cur: Cursor, dbName: String) -> Bool {
        let i = getColumnIndex(cur: cur, dbName: dbName)
        return i != -1 && !(cur.getString(i) ?? "").isEmpty
    }
    
    private func utcDateFromMs(_ ms: Int64) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
    
    private func isUtcTimeZone(_ tz: String?) -> Bool {
        guard let tz = tz, !tz.isEmpty else {
            return true
        }
        let utz = tz.uppercased()
        return utz == "UTC" || utz == "UTC-0" || utz == "UTC+0" || utz.hasSuffix("/UTC")
    }
    
    private func getDateTime(cur: Cursor, dbName: String, dbTzName: String?, cal: Calendar?) -> Date? {
        let i = getColumnIndex(cur: cur, dbName: dbName)
        if i == -1 || cur.isNull(index: i) {
            Log_OC.e(SaveCalendar.TAG, "No valid \(dbName) column found, index: \(i)")
            return nil
        }
        
        if cal == nil {
            return utcDateFromMs(cur.getLong(index: i))
        } else if dbTzName == nil {
            Log_OC.e(SaveCalendar.TAG, "No valid tz \(dbName) column given")
        }
        
        let tz = getString(cur: cur, dbName: dbTzName!)
        let isUtc = isUtcTimeZone(tz)
        
        var dt = DateTime(isUtc: isUtc)
        if dt.isUtc() != isUtc {
            fatalError("UTC mismatch after construction")
        }
        dt.setTime(milliseconds: cur.getLong(index: i))
        if dt.isUtc() != isUtc {
            fatalError("UTC mismatch after setTime")
        }
        
        if !isUtc {
            if mTzRegistry == nil {
                mTzRegistry = TimeZoneRegistryFactory.getInstance().createRegistry()
                if mTzRegistry == nil {
                    fatalError("Failed to create TZ registry")
                }
            }
            if let t = mTzRegistry?.getTimeZone(tz) {
                dt.setTimeZone(t: t)
                if !mInsertedTimeZones.contains(t) {
                    cal?.getComponents().add(t.getVTimeZone())
                    mInsertedTimeZones.insert(t)
                }
            } else {
                Log_OC.e(SaveCalendar.TAG, "Unknown TZ \(tz), assuming UTC")
            }
        }
        return dt
    }
    
    private func copyProperty(_ list: PropertyList, eventName: String, cursor: Cursor, dbName: String) -> String? {
        do {
            if let value = getString(cursor, dbName) {
                let property = mPropertyFactory.createProperty(eventName)
                property.setValue(value)
                list.add(property)
                return value
            }
        } catch {
            // Ignored exceptions: IOException, URISyntaxException, ParseException
        }
        return nil
    }
    
    private func copyEnumProperty(_ l: inout PropertyList, evName: String, cur: Cursor, dbName: String, vals: [String]) {
        do {
            let i = getColumnIndex(cur: cur, dbName: dbName)
            if i != -1 && !cur.isNull(at: i) {
                let value = Int(cur.getLong(at: i))
                if value >= 0 && value < vals.count && vals[value] != nil {
                    let p = mPropertyFactory.createProperty(evName)
                    p.setValue(vals[value])
                    l.add(p)
                }
            }
        } catch {
            // Ignored exceptions
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
        
        mUidMs = max(mUidMs, Int64(Date().timeIntervalSince1970 * 1000))
        let uid = "\(mUidMs)\(mUidTail!)"
        mUidMs += 1
        
        return uid
    }
    
    private func upload(file: URL) {
        let backupFolder = activity.resources.getString(R.string.calendar_backup_folder) + OCFile.PATH_SEPARATOR
        
        let request = UploadRequest.Builder(user: user, filePath: file.path, destinationPath: backupFolder + file.lastPathComponent)
            .setFileSize(file.fileSize)
            .setNameConflictPolicy(.rename)
            .setCreateRemoteFolder(true)
            .setTrigger(.user)
            .setPostAction(.moveToApp)
            .setRequireWifi(false)
            .setRequireCharging(false)
            .build()
        
        let connection = TransferManagerConnection(activity: activity, user: user)
        connection.enqueue(request)
    }
}
