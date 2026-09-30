import Foundation

/// Dates « AAAA-MM-JJ » manipulées en UTC pur, comme sur le site : aucun décalage lié au fuseau du téléphone.
enum Day {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "fr_FR")
        return c
    }()
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static var formatters: [String: DateFormatter] = [:]

    static func date(_ s: String) -> Date { iso.date(from: s) ?? Date() }
    static func string(_ d: Date) -> String { iso.string(from: d) }
    static func add(_ s: String, _ days: Int) -> String {
        string(calendar.date(byAdding: .day, value: days, to: date(s)) ?? date(s))
    }
    static func addMonths(_ s: String, _ n: Int) -> String {
        string(calendar.date(byAdding: .month, value: n, to: date(s)) ?? date(s))
    }
    static func diff(_ a: String, _ b: String) -> Int {
        calendar.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }
    /// Aujourd'hui selon l'horloge locale de l'utilisateur, exprimé en date UTC.
    static var today: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }
    /// 0 = lundi … 6 = dimanche
    static func weekday(_ s: String) -> Int { (calendar.component(.weekday, from: date(s)) + 5) % 7 }
    static func month(_ s: String) -> Int { calendar.component(.month, from: date(s)) - 1 }
    static func dayOfMonth(_ s: String) -> Int { calendar.component(.day, from: date(s)) }
    static func daysInMonth(_ s: String) -> Int { calendar.range(of: .day, in: .month, for: date(s))?.count ?? 30 }

    /// Formatage français, ex. format("EEE d MMM") → « mer. 21 oct. »
    static func format(_ s: String, _ template: String) -> String {
        let f: DateFormatter
        if let cached = formatters[template] { f = cached } else {
            f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate(template)
            formatters[template] = f
        }
        return f.string(from: date(s))
    }
    static func short(_ s: String) -> String { format(s, "EEEdMMM") }
    static func long(_ s: String) -> String { format(s, "EEEEdMMMM") }
}

enum Fmt {
    static func time(_ m: Int) -> String {
        let v = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", v / 60, v % 60)
    }
    static func duration(_ m: Int) -> String { "\(m / 60) h \(String(format: "%02d", m % 60))" }
    static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n > 1 ? "s" : "")" }
    /// « U25032 » → « U2 5032 »
    static func flight(_ fn: String) -> String { fn.count > 2 ? "\(fn.prefix(2)) \(fn.dropFirst(2))" : fn }
}

/// Même hachage que le site (FNV-1a sur les unités UTF-16) : les prix sont identiques sur les deux supports.
func hash01(_ s: String) -> Double {
    var h: UInt32 = 2166136261
    for c in s.utf16 { h ^= UInt32(c); h = h &* 16777619 }
    return Double(h % 100000) / 100000
}
