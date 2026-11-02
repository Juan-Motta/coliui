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
        let value = entry[entry.index(after: equals)...]
        return !value.isEmpty && isSecret(name: String(entry[..<equals]), value: String(value))
    }

    /// The same rule for a name and value kept apart (the Run sheet).
    public static func isSecret(name: String, value: String) -> Bool {
        isSecretName(name) || value.contains(/:\/\/[^\/@\s:]+:[^\/@\s]+@/)
    }

    /// Names that hold credentials; the Run sheet uses it to hide what is typed before there is a value.
    public static func isSecretName(_ name: String) -> Bool {
        let upper = name.uppercased()
        return secretWords.contains { upper.contains($0) }
    }
}
