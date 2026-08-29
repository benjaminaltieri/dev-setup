## Git Workflow
- When creating a new git branch use my shortcut so that my name is automatically appended, e.g. git cob a_new_feature
- When updating a branch to pull in the latest main branch changes, use my shortcut for pull rebasing: git prom. If there are conflicts during the rebase, abort and ask me to manually pull in the changes
- Use git comp to checkout the main branch and pull the latest changes

### Git Worktree Workflow
For working on multiple issues simultaneously without context switching:

#### Setup Worktrees
```bash
# Create worktree structure (one-time setup)
mkdir -p .trees

# Create worktree branches for parallel work
CURRENT_BRANCH=$(git branch --show-current)  # Save current branch
git cob issue-name                           # Create new branch
git checkout $CURRENT_BRANCH                 # Switch back to saved branch
git wta issue-name                           # Create worktree (alias for worktree add)
```

#### Working with Worktrees
```bash
# List all worktrees
git worktree list

# Work in a specific worktree
cd .trees/issue-name

# Each worktree is independent - make commits, run tests, etc.
```

#### Cleaning Up
```bash
# After merging or abandoning work
git wtrf issue-name              # Force remove worktree (when wtr fails)
git branch -D benaltieri/issue-name  # Force delete branch
```

## GitHub PR Comment Response Workflow

When I ask you to respond to and resolve GitHub PR review comments:

### Step 0: Evaluate Comments
- **Assess each comment**: Analyze language for required vs. suggestion ("should", "consider" vs. "must", "needs")
- **Technical evaluation**: Determine feasibility, benefits, and implementation approach
- **Make recommendation**: Provide assessment and suggest whether to implement
- **Get approval**: Wait for user confirmation before implementing changes

### Step 1: Fetch Comments
- **REST API**: Use `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments` to get formal review comments
- **GraphQL for standalone**: If comment not found, use GraphQL to get standalone review comments:
  ```
  gh api graphql -f query='{
    repository(owner: "{owner}", name: "{repo}") {
      pullRequest(number: {pr_number}) {
        reviewThreads(first: 20) {
          nodes {
            id isResolved
            comments(first: 10) {
              nodes { id body author { login } createdAt }
            }
          }
        }
      }
    }
  }'
  ```

### Step 2: Implement Fixes
- **Make the changes**: Implement the requested improvements
- **Test functionality**: Verify changes work correctly
- **Commit and push**: Create descriptive commits with "🤖 Generated with Claude Code"

### Step 3: Reply to Comments
- **Get correct ID**: For standalone comments, convert GraphQL node ID to database ID:
  ```
  gh api graphql -f query='{
    node(id: "{graphql_node_id}") {
      ... on PullRequestReviewComment { databaseId }
    }
  }'
  ```
- **Reply format**: Use simple format: `--field body="🔧✨ Fixed by Claude"`
- **Reply endpoint**: `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies --method POST`

### Step 4: Resolve Threads
- **GraphQL mutation**: Use thread ID (not comment ID):
  ```
  gh api graphql -f query='mutation {
    resolveReviewThread(input: {threadId: "{thread_id}"}) {
      thread { id isResolved }
    }
  }'
  ```

### Key Discoveries:
- **Comment types**: Formal review comments vs. standalone review comments have different IDs
- **ID conversion**: GraphQL node IDs need conversion to database IDs for REST API
- **Reply format**: Keep simple with emoji + "Fixed by Claude" attribution
- **Evaluation first**: Always assess comments before implementing changes

## GitHub Actions Workflow Debugging

When I ask you to debug GitHub Actions workflow failures:

### Step 1: Fetch and Analyze Job Logs
- **If workflow info not provided**: Use these commands to quickly find failures:
  - `gh run list --branch {current_branch} --status failure --limit 3` - Show only failed runs on current branch
  - `gh pr checks` - Show checks for current PR (if on feature branch)
- **Quick failure details**: `gh run view {run_id}` - Shows failed job IDs without downloading logs
- **Get job logs**: Use `gh api repos/{owner}/{repo}/actions/jobs/{job_id}/logs` for full logs or `gh run view {run_id} --log-failed` for failed jobs only
- **Identify failure point**: Look for error messages, stack traces, and the specific step that failed
- **Extract key details**: Note project IDs, regions, service accounts, operation IDs, and environment context from logs

### Step 2: Diagnose Common Issues

#### Permissions Issues (403 Errors)
- **Check authentication**: Verify tokens, service accounts, and credential configuration
- **Review access permissions**: Ensure the actor has required permissions for the specific action
- **Cross-service permissions**: Check if workflow needs access to external services (cloud providers, APIs)

#### Configuration Issues (400 Errors)
- **Parameter validation**: Check for invalid values, wrong formats, or missing required parameters
- **Resource constraints**: Verify quotas, limits, and resource availability
- **Environment mismatches**: Look for staging vs production configuration differences

#### Dependency Issues
- **Package installation**: Check for missing dependencies, version conflicts, or installation failures
- **Tool availability**: Ensure required tools and CLIs are installed and accessible
- **Path and environment variables**: Verify all required paths and variables are set correctly

### Step 3: Check GitHub Configuration
- **List repository variables**: `gh variable list`
- **Check environment-specific variables**: `gh variable list --env {environment}`
- **Compare environments**: Look for differences in configuration between staging, production, etc.
- **Review secrets**: Ensure all required secrets are present and accessible

### Step 4: Apply Fixes
- **Update repository variables**: `echo "{new_value}" | gh variable set {VAR_NAME}`
- **Update environment variables**: `echo "{new_value}" | gh variable set {VAR_NAME} --env {environment}`
- **Verify changes**: `gh variable list --env {environment}` to confirm updates

### Step 5: Verify and Validate
- **Re-run workflow**: Test the fix by triggering the workflow again
- **Monitor logs**: Check that the previously failing step now succeeds
- **Cross-environment testing**: If applicable, verify fix works across all environments

### Deployment-Specific Debugging

When debugging **cloud deployment failures** specifically:

#### Cloud Service Account Issues
- **Check service account roles**: `gcloud projects get-iam-policy {project_id} --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:{service_account_email}"`
- **Verify role permissions**: `gcloud iam roles describe {role} --format="value(includedPermissions)" | grep {specific_permission}`
- **Check API enablement**: `gcloud services list --enabled --project={project_id} --format="value(name)" | grep {api_name}`

#### Resource Location and Regional Issues
- **Invalid locations**: Common example - using zone names (us-central1a) instead of region names (us-central1) for services that require regions
- **Service availability**: Verify the service is available in the specified region
- **Cross-project permissions**: Ensure service account has roles in all required projects

#### Infrastructure Configuration
- **Compare actual vs expected**: Check if deployed resources match configuration
- **Cross-project deployments**: Verify permissions across staging and production projects
- **Workload identity**: Ensure federation and impersonation are properly configured

### Common Fixes Applied:
- **Misconfigured variables**: Example - invalid GCS location (us-central1a → us-central1) in environment variables
- **Missing permissions**: Added required service-specific roles to service accounts
- **Intermittent failures**: Rerun jobs as some failures are transient (quotas, rate limits, API throttling)
- **Environment drift**: Synchronized configuration between staging and production environments

### Key Discoveries:
- **Environment variables override repository variables**: Always check environment-specific settings first
- **Service-specific requirements**: Different cloud services have different location/region requirements
- **Configuration drift**: Actual settings may differ from expected configuration over time
- **Cross-environment consistency**: Ensure consistent configuration across all deployment environments

## Python Development Guidelines
- When building scripts in python from scratch, always prefer click over argparse
- for python project managed by poetry, use pyenv version to see which python is in use and pyenv local to set the version to use
- use my git au alias for lazily adding all tracked files instead of git add . to avoid accidentally adding untracked files. Only use git add directly when you are adding new files you have created. Always double check a git add on directories in case the .gitignore doesn't include patterns that should be in place to avoid unwanted adds
- my github handle is BEA01_qss
- use gh pr view --web to open pull requests in a browser after opening them
- I am using a newer version of poetry. When locking, the --no-update flag is no longer available since the no update behavior is default for 2.x and above
