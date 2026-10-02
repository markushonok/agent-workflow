include "Technical Design/Validate";
include "Behavior/Validate";

def failure_valid:
  type == "object" and
  keys == ["error", "status"] and
  .status == "failed" and
  (.error | type == "object" and keys == ["kind", "message"] and
    (.kind as $kind |
      ["configuration", "review_failed"] | index($kind) != null) and
    (.message | type == "string" and length > 0));

def parent_valid:
  type == "object" and
  keys == ["behavior", "design", "status"] and
  (.status == "completed" or .status == "incomplete") and
  (.design | (design_valid or failure_valid)) and
  (.behavior | (behavior_valid or failure_valid)) and
  (if .status == "completed"
   then (.design | design_valid) and (.behavior | behavior_valid)
   else (.design | failure_valid) or (.behavior | failure_valid)
   end);

if length == 1 and (.[0] | parent_valid) then .[0] else error("Invalid parent review") end