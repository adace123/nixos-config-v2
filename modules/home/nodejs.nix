{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    nodejs # Provides node and npm
    # Bun - Fast all-in-one JavaScript runtime (default)
    bun # JavaScript runtime, bundler, test runner, package manager

    # Node.js for compatibility (available via node22/node20 commands)
    # nodejs_22 is available via alias 'node22' command
    # nodejs_20 is available via alias 'node20' command

    # Development tools (using nodePackages for LSP/tools)
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.vscode-langservers-extracted # HTML, CSS, JSON, ESLint LSP
    nodePackages.prettier
    nodePackages.eslint
    nodePackages.npm-check-updates # Update package.json dependencies

    # Build and dev tools
    nodePackages.nodemon

    # Utilities
    nodePackages.serve # Static file server
    nodePackages.http-server # Simple HTTP server
  ];

  # Bun and JavaScript environment configuration
  home.sessionVariables = {
    # Bun configuration (default runtime)
    BUN_INSTALL = "$HOME/.bun";

    # Node configuration (for compatibility)
    NODE_OPTIONS = "--max-old-space-size=4096"; # Increase memory limit

    # npm configuration
    NPM_CONFIG_FUND = "false"; # Disable npm funding messages
    NPM_CONFIG_AUDIT = "false"; # Disable automatic audit on install
    NPM_CONFIG_UPDATE_NOTIFIER = "false"; # Disable update notifications

    # pnpm configuration
    PNPM_HOME = "$HOME/.local/share/pnpm";
  };

  # Update PATH for package managers (Bun first for priority)
  home.sessionPath = [
    "$HOME/.bun/bin"
    "$HOME/.local/share/pnpm"
  ];

  # Shell aliases for JavaScript development
  programs.zsh.shellAliases = {
    # Node version management (use bun as default, node via explicit versions)
    node = "bun"; # Bun can run Node.js code
    node22 = "${pkgs.nodejs_22}/bin/node";
    node20 = "${pkgs.nodejs_20}/bin/node";
    npm = "bun"; # Bun replaces npm
    npm22 = "${pkgs.nodejs_22}/bin/npm";
    npm20 = "${pkgs.nodejs_20}/bin/npm";

    # npm shortcuts (using bun)
    ni = "bun install";
    nis = "bun add";
    nid = "bun add --dev";
    nig = "bun add --global";
    nr = "bun run";
    nrs = "bun run start";
    nrb = "bun run build";
    nrt = "bun test";
    nrd = "bun run dev";
    nu = "bun update";
    ncu = "npm-check-updates";

    # pnpm shortcuts
    pn = "pnpm";
    pni = "pnpm install";
    pna = "pnpm add";
    pnad = "pnpm add -D";
    pnr = "pnpm run";
    pnrs = "pnpm run start";
    pnrb = "pnpm run build";
    pnrt = "pnpm run test";
    pnrd = "pnpm run dev";

    # yarn shortcuts
    yi = "yarn install";
    ya = "yarn add";
    yad = "yarn add --dev";
    yr = "yarn run";
    yrs = "yarn run start";
    yrb = "yarn run build";
    yrt = "yarn run test";
    yrd = "yarn run dev";

    # Bun shortcuts
    b = "bun";
    bi = "bun install";
    ba = "bun add";
    bad = "bun add --dev";
    br = "bun run";
    brs = "bun run start";
    brb = "bun run build";
    brt = "bun test";
    brd = "bun run dev";
    bx = "bunx"; # Like npx
  };

  # Bun configuration (replaces .npmrc as default)
  home.file.".bunfig.toml".text = ''
    # Install behavior
    [install]
    exact = true
    production = false
    optional = true
    dev = true
    peer = true
    frozen = false

    # Performance
    cache = "~/.bun/install/cache"

    # Registry
    registry = "https://registry.npmjs.org"

    # Lockfile
    lockfile = true
  '';

  # npm configuration (for when using Node directly)
  home.file.".npmrc".text = ''
    # Performance
    prefer-offline=true
    progress=false

    # Security
    audit=false
    fund=false

    # Package installation
    save-exact=true
    engine-strict=true

    # Display
    unicode=true
  '';

  # pnpm configuration
  home.file.".config/pnpm/rc".text = ''
    # Store configuration
    store-dir=~/.local/share/pnpm/store

    # Performance
    prefer-offline=true

    # Lockfile
    lockfile=true

    # Display
    reporter=default
  '';
}
