
import Foundation

class AlphanumComparator<T: CustomStringConvertible>: Comparator, Serializable {
    private static func isDigit(_ ch: Character) -> Bool {
        return ch.asciiValue! >= 48 && ch.asciiValue! <= 57
    }

    private static func isSpecialChar(_ ch: Character) -> Bool {
        let asciiValue = ch.asciiValue ?? 0
        return asciiValue <= 47 || (asciiValue >= 58 && asciiValue <= 64) || (asciiValue >= 91 && asciiValue <= 96) || (asciiValue >= 123 && asciiValue <= 126)
    }

    private static func getChunk(_ string: String, _ stringLength: Int, _ marker: inout Int) -> String {
        var chunk = ""
        var c = string[string.index(string.startIndex, offsetBy: marker)]
        chunk.append(c)
        marker += 1
        if isDigit(c) {
            while marker < stringLength {
                c = string[string.index(string.startIndex, offsetBy: marker)]
                if !isDigit(c) {
                    break
                }
                chunk.append(c)
                marker += 1
            }
        } else if !isSpecialChar(c) {
            while marker < stringLength {
                c = string[string.index(string.startIndex, offsetBy: marker)]
                if isDigit(c) || isSpecialChar(c) {
                    break
                }
                chunk.append(c)
                marker += 1
            }
        }
        return chunk
    }

    static func compare(_ o1: ServerFileInterface, _ o2: ServerFileInterface) -> Int {
        let s1 = o1.getFileName()
        let s2 = o2.getFileName()
        
        return compare(s1, s2)
    }

    static func compare(_ f1: URL, _ f2: URL) -> Int {
        let s1 = f1.path
        let s2 = f2.path

        return compare(s1, s2)
    }

    func compare(_ t1: T, _ t2: T) -> Int {
        return compare(t1.description, t2.description)
    }

    static func compare(_ s1: String, _ s2: String) -> Int {
        var thisMarker = 0
        var thatMarker = 0
        let s1Length = s1.count
        let s2Length = s2.count

        while thisMarker < s1Length && thatMarker < s2Length {
            let thisChunk = getChunk(s1, s1Length, &thisMarker)
            thisMarker += thisChunk.count

            let thatChunk = getChunk(s2, s2Length, &thatMarker)
            thatMarker += thatChunk.count

            var result = 0
            if isDigit(thisChunk.first!) && isDigit(thatChunk.first!) {
                var thisChunkZeroCount = 0
                var zero = true
                var countThis = 0
                while countThis < thisChunk.count && isDigit(thisChunk[thisChunk.index(thisChunk.startIndex, offsetBy: countThis)]) {
                    if zero {
                        if thisChunk[thisChunk.index(thisChunk.startIndex, offsetBy: countThis)] == "0" {
                            thisChunkZeroCount += 1
                        } else {
                            zero = false
                        }
                    }
                    countThis += 1
                }

                var thatChunkZeroCount = 0
                var countThat = 0
                zero = true
                while countThat < thatChunk.count && isDigit(thatChunk[thatChunk.index(thatChunk.startIndex, offsetBy: countThat)]) {
                    if zero {
                        if thatChunk[thatChunk.index(thatChunk.startIndex, offsetBy: countThat)] == "0" {
                            thatChunkZeroCount += 1
                        } else {
                            zero = false
                        }
                    }
                    countThat += 1
                }

                let thisChunkValue = BigInt(thisChunk.prefix(countThis))!
                let thatChunkValue = BigInt(thatChunk.prefix(countThat))!

                result = thisChunkValue.compare(thatChunkValue)

                if result == 0 {
                    result = thisChunkZeroCount - thatChunkZeroCount

                    if result != 0 {
                        return result
                    }
                } else {
                    return result
                }
            } else if isSpecialChar(thisChunk.first!) && isSpecialChar(thatChunk.first!) {
                for i in 0..<thisChunk.count {
                    let thisChar = thisChunk[thisChunk.index(thisChunk.startIndex, offsetBy: i)]
                    let thatChar = thatChunk[thatChunk.index(thatChunk.startIndex, offsetBy: i)]
                    if thisChar == "." && thatChar != "." {
                        return -1
                    } else if thatChar == "." && thisChar != "." {
                        return 1
                    } else {
                        result = thisChar.asciiValue! - thatChar.asciiValue!
                        if result != 0 {
                            return result
                        }
                    }
                }
            } else if isSpecialChar(thisChunk.first!) && !isSpecialChar(thatChunk.first!) {
                return -1
            } else if !isSpecialChar(thisChunk.first!) && isSpecialChar(thatChunk.first!) {
                return 1
            } else {
                result = thisChunk.compare(thatChunk, options: .caseInsensitive)
            }

            if result != 0 {
                return result
            }
        }

        return s1Length - s2Length
    }
}
