{
  pkgs,
  inputs,
  ...
}:

let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
in

{
  programs.pi-coding-agent = {
    enable = true;
    package = llmAgents.pi;
    extraPackages = [
      pkgs.git
      pkgs.nodejs
      pkgs.bun
    ];
    settings = {
      packages = [
        "git:github.com/otahontas/pi-coding-agent-catppuccin"
        "npm:pi-powerline-footer"
        "npm:pi-web-access"
        "npm:context-mode"
        "npm:@juicesharp/rpiv-todo"
      ];
    };
  };
}
