/// Docker's rule for container, volume and network names.
public enum DockerName {
    /// Why `name` can't be used, or nil when it can.
    public static func formatError(_ name: String) -> String? {
        guard name.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$"#, options: .regularExpression) == nil else { return nil }
        return "Names can use letters, digits, “_”, “.” and “-”, and must start with a letter or digit."
    }
}
