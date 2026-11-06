# Derive Foundry's named ABI serialization description from the compiler's recipeSpec() output.
# Enum ABI types already have their canonical uint width; tuple names/fields come from compiler ABI.
def struct_name:
  .internalType | sub("^struct "; "") | sub("(\\[[0-9]*\\])+$"; "")
  | if test("^[A-Za-z_][A-Za-z0-9_]*$") then . else error("unsupported ABI struct name: " + .) end;
def field_type:
  if (.type | startswith("tuple")) then struct_name + (.type | ltrimstr("tuple")) else .type end;
def definitions:
  if (.type | startswith("tuple")) then
    {name: struct_name, fields: [.components[] | {name, type: field_type}]},
    (.components[] | definitions)
  else empty end;
def declaration:
  .name + "(" + ([.fields[] | .type + " " + .name] | join(",")) + ")";
[.abi[] | select(.type == "function" and .name == "recipeSpec" and (.inputs | length) == 0)] as $methods
| if ($methods | length) != 1 or ($methods[0].outputs | length) != 1 then
    error("one recipeSpec() struct output is required")
  else $methods[0].outputs[0] end
| if .type != "tuple" then error("recipeSpec() must return a struct") else . end
| . as $root
| ($root | struct_name) as $primary
| [definitions] | group_by(.name)
| map(if ([.[] | declaration] | unique | length) != 1 then error("conflicting ABI struct definitions") else .[0] end)
| sort_by([if .name == $primary then 0 else 1 end, .name])
| map(declaration) | join("")
