include "Technical Design/Validate";
include "Behavior/Validate";

def ledger_valid:
  (design_content_valid or behavior_content_valid) and
  (if .finalized then all(.files[]; .covered == true) else true end);