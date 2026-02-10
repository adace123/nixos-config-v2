{
  inputs,
  pkgs,
}:
{
  rules = {
    code-quality = ''
      # Code Quality Rules

      ## General Guidelines
      - Write clean, readable code with meaningful variable names
      - Use proper error handling and avoid silent failures
      - Follow existing code style and conventions in the project
      - Add comments for complex logic, not for obvious operations

      ## Security
      - Never log or expose secrets, API keys, or credentials
      - Validate all user inputs
      - Use parameterized queries for database operations
    '';

    best-practices = ''
      # Best Practices

      - Keep functions small and focused on a single task
      - Prefer composition over inheritance
      - Write tests for critical functionality
      - Use descriptive names for variables and functions
    '';
  };

  agents = {
    code-reviewer = {
      opencode = ''
        # Code Reviewer Agent

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

      claude-code = ''
        ---
        name: code-reviewer
        description: Specialized code review agent
        tools: Read, Edit, Grep, Bash
        ---

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
    };
  };

  commands = {
    changelog = {
      opencode = ''
        # Update Changelog

        Update CHANGELOG.md with a new entry for the specified version.
        Follow the Keep a Changelog format: https://keepachangelog.com/

        Usage: /changelog [version] [change-type] [message]
        Change types: Added, Changed, Deprecated, Removed, Fixed, Security
      '';

      claude-code = ''
        ---
        allowed-tools: Bash(git log:*), Bash(git diff:*), Edit
        argument-hint: [version] [change-type] [message]
        description: Update CHANGELOG.md with new entry
        ---
        Parse the version, change type, and message from the input
        and update the CHANGELOG.md file accordingly.
        Follow the Keep a Changelog format: https://keepachangelog.com/
      '';
    };

    commit = {
      opencode = ''
        # Create Commit

        Create a properly formatted conventional git commit message.

        Format:
        - Use imperative mood ("Add feature" not "Added feature")
        - First line: brief summary (50 chars max)
        - Body: detailed explanation if needed
        - Reference issues with "Fixes #123" or "Closes #456"
      '';

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

  skills = {
    beads = "${
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.beads.src
    }/claude-plugin/skills/beads";
  };
}
