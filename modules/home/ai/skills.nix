# Shared agent skills, sourced from the mattpocock-skills flake input so they
# stay in sync with upstream (see github:mattpocock/skills).
#
# Exposes two views over the same skill list:
#   - piFiles:      home.file entries for Pi (~/.pi/agent/skills/, auto-discovered)
#   - claudeSkills: programs.claude-code.skills entries (whole skill directory,
#                   so supporting files like tdd's tests.md/mocking.md are copied)
{
  inputs,
  ...
}:

let
  # Paths relative to skills/ in the input.
  commonSkills = [
    "productivity/grilling"
    "productivity/grill-me"
    "engineering/tdd"
  ];

  skillsRoot = "${inputs.mattpocock-skills}/skills";

  skillName = path: baseNameOf path;

  mkPiFile = path: {
    source = "${skillsRoot}/${path}";
    recursive = true;
  };

  # Directory path — the claude-code module detects a store directory and
  # copies the whole skill (SKILL.md plus any supporting files).
  mkClaudeSkill = path: "${skillsRoot}/${path}";
in
{
  piFiles = builtins.listToAttrs (
    map (path: {
      name = ".pi/agent/skills/${skillName path}";
      value = mkPiFile path;
    }) commonSkills
  );

  claudeSkills = builtins.listToAttrs (
    map (path: {
      name = skillName path;
      value = mkClaudeSkill path;
    }) commonSkills
  );
}
