import Foundation

/// Allocation-free, locale-independent date parsing for the formats IPTV back-ends use.
///
/// `DateFormatter` is avoided on purpose: it is slow for hundreds of thousands of EPG rows and
/// its behaviour depends on the device locale/calendar.
public enum DateParsing {
    /// Parses an XMLTV timestamp: `yyyyMMddHHmmss ±HHMM`.
    ///
    /// Also accepts `yyyyMMddHHmm` (seconds omitted), `±HH:MM` offsets, the literal `Z`,
    /// and a missing zone, which is treated as UTC.
    public static func xmltv(_ string: String) -> Date? {
        let bytes = Array(string.utf8)
        var i = 0
        func readDigits(_ count: Int) -> Int? {
            guard i + count <= bytes.count else { return nil }
            var value = 0
            for k in 0..<count {
                let b = bytes[i + k]
                guard b >= 0x30 && b <= 0x39 else { return nil }
                value = value * 10 + Int(b - 0x30)
            }
            i += count
            return value
        }
        while i < bytes.count, bytes[i] == 0x20 { i += 1 }
        guard let year = readDigits(4), let month = readDigits(2), let day = readDigits(2),
              let hour = readDigits(2), let minute = readDigits(2) else { return nil }
        var second = 0
        if i + 2 <= bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
            guard let s = readDigits(2) else { return nil }
            second = s
        }
        guard let base = epochSeconds(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        else { return nil }

        while i < bytes.count, bytes[i] == 0x20 { i += 1 }
        guard i < bytes.count else { return Date(timeIntervalSince1970: TimeInterval(base)) }
        if bytes[i] == UInt8(ascii: "Z") || bytes[i] == UInt8(ascii: "z") {
            return Date(timeIntervalSince1970: TimeInterval(base))
        }
        let sign: Int
        switch bytes[i] {
        case UInt8(ascii: "+"): sign = 1
        case UInt8(ascii: "-"): sign = -1
        default: return nil
        }
        i += 1
        guard let offHours = readDigits(2) else { return nil }
        if i < bytes.count, bytes[i] == UInt8(ascii: ":") { i += 1 }
        let offMinutes = readDigits(2) ?? 0
        guard offHours <= 14, offMinutes < 60 else { return nil }
        let offset = sign * (offHours * 3600 + offMinutes * 60)
        return Date(timeIntervalSince1970: TimeInterval(base - offset))
    }

    /// Parses Unix epoch seconds given as text (`"1790000000"`), as used by Xtream.
    public static func unixTimestamp(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty,
              let seconds = Double(string) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Parses `yyyy-MM-dd HH:mm:ss`, treated as UTC (Xtream `start`/`end` fallback fields).
    public static func xtreamDateTime(_ string: String) -> Date? {
        let digits = string.filter(\.isNumber)
        guard digits.count == 14 else { return nil }
        return xmltv(digits)
    }

    /// Seconds since 1970-01-01T00:00:00Z for a proleptic Gregorian UTC date-time, or `nil` if out of range.
    static func epochSeconds(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Int? {
        guard (1...12).contains(month), (1...daysInMonth(year: year, month: month)).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second) else { return nil }
        return daysFromCivil(year: year, month: month, day: day) * 86_400 + hour * 3600 + minute * 60 + second
    }

    /// Howard Hinnant's days-from-civil algorithm.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}
