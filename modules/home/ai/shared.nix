_:

let
  codeReviewerCore = ''
    You are a senior software engineer specializing in code reviews.

    ## Focus Areas
    - Code quality, readability, and maintainability
    - Security vulnerabilities and edge cases
    - Performance issues and optimization opportunities
    - Consistency with project conventions

    ## Guidelines
    - Review for potential bugs and edge cases
    - Check for security vulnerabilities (SQL injection, XSS, etc.)
    - Ensure code follows best practices and DRY principles
    - Suggest improvements for readability and performance
    - Be constructive and provide actionable feedback
  '';
in
{
  agents = {
    # Pinned rather than inherited: this agent is exempt from the
    # CLAUDE_CODE_SUBAGENT_MODEL default set in claude.nix, because a model in
    # agent frontmatter takes precedence over that variable. Review is
    # unrewarded judgement with no downstream checker, so it should not ride
    # the cheap default. Sonnet 5.5 matches Opus 5.5 on Terminal-Bench 4.0 at
    # half the token price.
    code-reviewer = {
      claude-code = ''
        ---
        name: code-reviewer
        description: Specialized code review agent
        model: claude-sonnet-5-5
        tools: Read, Edit, Grep, Bash
        ---

        ${codeReviewerCore}
      '';
    };
  };

  commands = {
    changelog = {
      claude-code = ''
        ---
        allowed-tools: Bash(git log:*), Bash(git diff:*), Edit
        argument-hint: [version] [change-type] [message]
        description: Update CHANGELOG.md with new entry
        ---
        Parse the version, change type, and message from the input
        and update the CHANGELOG.md file accordingly.
        Follow the Keep a Changelog format: https://keepachangelog.com/

        Keep entries concise: one short line per change, describing what changed
        from a user's point of view. Rationale, file names, and investigation
        notes belong in the commit message, not the changelog. If the project's
        CLAUDE.md defines its own changelog conventions, follow those instead.
      '';
    };

    commit = {
      claude-code = ''
        ---
        allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*)
        description: Create a git commit with proper message
        ---
        ## Context

        - Current git status: !`git status`
        - Current git diff: !`git diff HEAD`
        - Recent commits: !`git log --oneline -5`

        ## Task

        Based on the changes above, create a single atomic git commit with a descriptive message.
        Use imperative mood and follow conventional commits format.
      '';
    };
  };
}
