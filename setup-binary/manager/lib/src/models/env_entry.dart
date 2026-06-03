/// describes one env value shown in the editor
class EnvEntry {
  /// @param key env variable name written to the env file
  /// @param value current value shown in the field
  /// @param description helper text shown under the field
  /// @param required whether startup validation needs a non placeholder value
  /// @param secret whether the field should hide the value while editing
  ///
  /// creates an env editor row from env example and env file values
  const EnvEntry({
    required this.key,
    required this.value,
    required this.description,
    required this.required,
    required this.secret,
  });

  final String key;
  final String value;
  final String description;
  final bool required;
  final bool secret;

  EnvEntry copyWith({
    String? value,
    String? description,
    bool? required,
    bool? secret,
  }) {
    return EnvEntry(
      key: key,
      value: value ?? this.value,
      description: description ?? this.description,
      required: required ?? this.required,
      secret: secret ?? this.secret,
    );
  }
}

/// describes whether env values are ready to start core
class EnvValidationResult {
  /// @param valid whether all required values are present
  /// @param missing required keys required env keys that blocked startup
  ///
  /// creates the validation result used before service startup
  const EnvValidationResult({
    required this.valid,
    required this.missingRequiredKeys,
  });

  final bool valid;
  final List<String> missingRequiredKeys;
}
