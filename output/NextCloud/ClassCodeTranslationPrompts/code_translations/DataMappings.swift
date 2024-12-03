
import Foundation
import Contacts

class DataMappings {
    private static let phoneTypeMappings: [TelephoneType: Int] = {
        var m = [TelephoneType: Int]()
        m[.BBS] = CNLabelPhoneNumberOther
        m[.CAR] = CNLabelPhoneNumberCar
        m[.CELL] = CNLabelPhoneNumberMobile
        m[.FAX] = CNLabelPhoneNumberHomeFax
        m[.HOME] = CNLabelPhoneNumberHome
        m[.ISDN] = CNLabelPhoneNumberISDN
        m[.MODEM] = CNLabelPhoneNumberOther
        m[.PAGER] = CNLabelPhoneNumberPager
        m[.MSG] = CNLabelPhoneNumberMMS
        m[.PCS] = CNLabelPhoneNumberOther
        m[.TEXT] = CNLabelPhoneNumberMMS
        m[.TEXTPHONE] = CNLabelPhoneNumberMMS
        m[.VIDEO] = CNLabelPhoneNumberOther
        m[.WORK] = CNLabelPhoneNumberWork
        m[.VOICE] = CNLabelPhoneNumberOther
        return m
    }()
    
    private static let websiteTypeMappings: [String: Int] = {
        var m = [String: Int]()
        m["home"] = CNLabelURLAddressHome
        m["work"] = CNLabelURLAddressWork
        m["homepage"] = CNLabelURLAddressHomePage
        m["profile"] = CNLabelURLAddressProfile
        return m
    }()
    
    private static let emailTypeMappings: [EmailType: Int] = {
        var m = [EmailType: Int]()
        m[.HOME] = CNLabelHome
        m[.WORK] = CNLabelWork
        return m
    }()
    
    private static let addressTypeMappings: [AddressType: Int] = {
        var m = [AddressType: Int]()
        m[.HOME] = CNLabelHome
        m[AddressType.get("business")] = CNLabelWork
        m[.WORK] = CNLabelWork
        m[AddressType.get("other")] = CNLabelOther
        return m
    }()
    
    private static let abRelatedNamesMappings: [String: Int] = {
        var m = [String: Int]()
        m["father"] = CNLabelContactRelationFather
        m["spouse"] = CNLabelContactRelationSpouse
        m["mother"] = CNLabelContactRelationMother
        m["brother"] = CNLabelContactRelationBrother
        m["parent"] = CNLabelContactRelationParent
        m["sister"] = CNLabelContactRelationSister
        m["child"] = CNLabelContactRelationChild
        m["assistant"] = CNLabelContactRelationAssistant
        m["partner"] = CNLabelContactRelationPartner
        m["manager"] = CNLabelContactRelationManager
        return m
    }()
    
    private static let abDateMappings: [String: Int] = {
        var m = [String: Int]()
        m["anniversary"] = CNLabelDateAnniversary
        m["other"] = CNLabelDateOther
        return m
    }()
    
    private static let imPropertyNameMappings: [String: Int] = {
        var m = [String: Int]()
        m["X-AIM"] = CNInstantMessageAddress.IMProtocolAIM.rawValue
        m["X-ICQ"] = CNInstantMessageAddress.IMProtocolICQ.rawValue
        m["X-QQ"] = CNInstantMessageAddress.IMProtocolICQ.rawValue
        m["X-GOOGLE-TALK"] = CNInstantMessageAddress.IMProtocolCustom.rawValue
        m["X-JABBER"] = CNInstantMessageAddress.IMProtocolJabber.rawValue
        m["X-MSN"] = CNInstantMessageAddress.IMProtocolMSN.rawValue
        m["X-MS-IMADDRESS"] = CNInstantMessageAddress.IMProtocolMSN.rawValue
        m["X-YAHOO"] = CNInstantMessageAddress.IMProtocolYahoo.rawValue
        m["X-SKYPE"] = CNInstantMessageAddress.IMProtocolSkype.rawValue
        m["X-SKYPE-USERNAME"] = CNInstantMessageAddress.IMProtocolSkype.rawValue
        m["X-TWITTER"] = CNInstantMessageAddress.IMProtocolCustom.rawValue
        return m
    }()
    
    private static let imProtocolMappings: [String: Int] = {
        var m = [String: Int]()
        m["aim"] = CNInstantMessageAddress.IMProtocolAIM.rawValue
        m["icq"] = CNInstantMessageAddress.IMProtocolICQ.rawValue
        m["msn"] = CNInstantMessageAddress.IMProtocolMSN.rawValue
        m["ymsgr"] = CNInstantMessageAddress.IMProtocolYahoo.rawValue
        m["skype"] = CNInstantMessageAddress.IMProtocolSkype.rawValue
        return m
    }()
    
    static func getWebSiteType(_ type: String?) -> Int {
        if type == nil {
            return CNLabelURLAddressOther
        }
        
        let lowercasedType = type!.lowercased()
        let value = websiteTypeMappings[lowercasedType]
        return value ?? CNLabelURLAddressOther
    }
    
    static func getDateType(_ type: String?) -> Int {
        guard let type = type else {
            return CNLabelDateOther
        }
        
        let lowercasedType = type.lowercased()
        for (key, value) in abDateMappings {
            if lowercasedType.contains(key) {
                return value
            }
        }
        return CNLabelDateOther
    }
    
    static func getNameType(_ type: String?) -> Int {
        guard let type = type else {
            return CNLabelContactRelationCustom
        }
        
        let lowercasedType = type.lowercased()
        for (key, value) in abRelatedNamesMappings {
            if lowercasedType.contains(key) {
                return value
            }
        }
        return CNLabelContactRelationCustom
    }
    
    static func getImPropertyNameMappings() -> [String: Int] {
        return imPropertyNameMappings
    }
    
    static func getIMTypeFromProtocol(_ protocol: String?) -> Int {
        guard let protocol = protocol else {
            return CNInstantMessageAddress.IMProtocolCustom.rawValue
        }
        
        let lowercasedProtocol = protocol.lowercased()
        let value = imProtocolMappings[lowercasedProtocol]
        return value ?? CNInstantMessageAddress.IMProtocolCustom.rawValue
    }
    
    static func getPhoneType(_ property: Telephone) -> Int {
        for type in property.getTypes() {
            if let androidType = phoneTypeMappings[type] {
                return androidType
            }
        }
        return CNLabelPhoneNumberOther
    }
    
    static func getEmailType(_ property: Email) -> Int {
        for type in property.getTypes() {
            if let androidType = emailTypeMappings[type] {
                return androidType
            }
        }
        return CNLabelOther
    }
    
    static func getAddressType(property: Address) -> Int {
        for type in property.getTypes() {
            if let iosType = addressTypeMappings[type] {
                return iosType
            }
        }
        return CNLabelOther
    }
    
    private init() {
        //hide constructor
    }
}
