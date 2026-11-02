/// Hides environment values that look like credentials, so they don't show (or get copied) by accident.
public enum SecretMask {
    public static let placeholder = "••••••"
    static let secretWords = ["PASS", "SECRET", "TOKEN", "KEY", "CREDENTIAL", "AUTH", "PRIVATE"]

    /// `NAME=value` with a secret-looking name, or a URL carrying a password, becomes `NAME=••••••`.
    public static func masked(_ entry: String) -> String {
        guard let equals = entry.firstIndex(of: "=") else { return entry }
        let name = entry[..<equals].uppercased()
        let value = entry[entry.index(after: equals)...]
        guard !value.isEmpty else { return entry }
        let isSecret = secretWords.contains { name.contains($0) }
            || value.contains(/:\/\/[^\/@\s:]+:[^\/@\s]+@/)
        return isSecret ? entry[...equals] + placeholder : entry
    }
}
