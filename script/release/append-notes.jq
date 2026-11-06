# Replace only our bounded block, preserving maintainer text on either side.
def start: "<!-- lattice-shared-contracts:start -->";
def finish: "<!-- lattice-shared-contracts:end -->";
.body as $body |
if ($body|contains(start)) or ($body|contains(finish)) then
  ($body|split(start)) as $left |
  if ($left|length)!=2 then error("ambiguous release notes start marker") else
    ($left[1]|split(finish)) as $right |
    if ($right|length)!=2 then error("ambiguous release notes end marker") else
      $left[0]+start+"\n"+$notes+finish+$right[1]
    end
  end
else $body+"\n\n"+start+"\n"+$notes+finish+"\n" end
