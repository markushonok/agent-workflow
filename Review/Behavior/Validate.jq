def behavior_content_valid:
  type == "object" and keys == ["changed_files", "dimension", "files", "finalized", "findings", "rules"] and
  .dimension == "behavior" and .rules == [] and (.finalized | type == "boolean") and
  (.changed_files | type == "array" and unique == . and all(.[]; type == "string" and length > 0)) and
  (.files | keys) == .changed_files and
  (.files | type == "object") and (.findings | type == "array") and
  .files as $files |
  all(.files | to_entries[];
    (.key | length > 0) and
    (.value | type == "object" and keys == ["covered"] and (.covered | type == "boolean"))) and
  all(.findings[];
    type == "object" and keys == ["actual", "area", "expected", "explanation", "file", "scenario"] and
    all(.[]; type == "string" and length > 0) and
    .file as $file | $files | has($file));

def behavior_valid:
  behavior_content_valid and .finalized == true and all(.files[]; .covered == true);