def design_content_valid:
  type == "object" and keys == ["changed_files", "dimension", "files", "finalized", "findings", "rules"] and
  .dimension == "design" and (.finalized | type == "boolean") and
  (.changed_files | type == "array" and unique == . and all(.[]; type == "string" and length > 0)) and
  (.files | keys) == .changed_files and
  (.rules | type == "array" and length > 0 and all(.[]; type == "string" and length > 0) and unique == .) and
  (.files | type == "object") and (.findings | type == "array") and
  .rules as $rules | .files as $files |
  all(.files | to_entries[];
    (.key | length > 0) and
    (.value | type == "object" and keys == ["covered", "rules"] and
      (.covered | type == "boolean") and
      (.rules | type == "array" and unique == . and all(.[]; . as $rule | $rules | index($rule) != null)))) and
  all(.findings[];
    type == "object" and keys == ["file", "finding", "provision", "rule"] and
    all(.[]; type == "string" and length > 0) and
    .file as $file | .rule as $rule |
    ($files | has($file)) and ($files[$file].rules | index($rule) != null));

def design_valid:
  design_content_valid and .finalized == true and all(.files[]; .covered == true);