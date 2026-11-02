/// Hides environment values that look like credentials, so they don't show (or get copied) by accident.
public enum SecretMask {
    public static let placeholder = "••••••"
    static let secretWords = ["PASS", "SECRET", "TOKEN", "KEY", "CREDENTIAL", "AUTH", "PRIVATE"]

    /// `NAME=value` with a secret-looking name, or a URL carrying a password, becomes `NAME=••••••`.
    public static func masked(_ entry: String) -> String {
        guard isSecret(entry), let equals = entry.firstIndex(of: "=") else { return entry }
        return entry[...equals] + placeholder
    }

    /// A non-empty value under a secret-looking name, or a URL carrying a password.
    public static func isSecret(_ entry: String) -> Bool {
        guard let equals = entry.firstIndex(of: "=") else { return false }
        let name = entry[..<equals].uppercased()
        let value = entry[entry.index(after: equals)...]
        guard !value.isEmpty else { return false }
        return secretWords.contains { name.contains($0) }
            || value.contains(/:\/\/[^\/@\s:]+:[^\/@\s]+@/)
    }
}
