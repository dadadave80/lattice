# The deliberately small schema vocabulary used by deployments/schema (no external schema runtime).
def check($s):
  . as $v |
  (if $s | has("anyOf") then any($s.anyOf[]; . as $a | $v | check($a)) else true end) and
  (if $s | has("const") then . == $s.const else true end) and
  (if $s | has("enum") then . as $x | any($s.enum[]; . == $x) else true end) and
  (if $s | has("type") then
     if $s.type == "integer" then type == "number" and floor == .
     else type == $s.type end
   else true end) and
  (if type == "string" then
     (if $s | has("pattern") then test($s.pattern) else true end) and
     (if $s | has("minLength") then length >= $s.minLength else true end)
   elif type == "number" then (if $s | has("minimum") then . >= $s.minimum else true end)
   elif type == "array" then
     (if $s | has("minItems") then length >= $s.minItems else true end) and
     (if $s | has("items") then all(.[]; check($s.items)) else true end)
   elif type == "object" then
     (if $s | has("required") then . as $o | all($s.required[]; . as $k | $o | has($k)) else true end) and
     (if $s.additionalProperties == false then (keys - ($s.properties | keys) | length) == 0 else true end) and
     (if $s | has("properties") then all(to_entries[]; .key as $k | .value | check($s.properties[$k] // {})) else true end)
   else true end);
def schema_supported:
  (keys - ["$schema","$id","title","type","required","properties","additionalProperties","items","anyOf","const","enum","pattern","minimum","minItems","minLength"] | length) == 0 and
  (if has("properties") then all(.properties[]; schema_supported) else true end) and
  (if has("items") then .items | schema_supported else true end) and
  (if has("anyOf") then all(.anyOf[]; schema_supported) else true end);
if ($schema[0] | schema_supported) then check($schema[0]) else error("unsupported schema vocabulary") end
