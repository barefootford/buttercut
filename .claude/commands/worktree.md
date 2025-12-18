# Create Worktree with Library

Create a new git worktree with all libraries and media from main.

## Arguments

`<branch-name>` - The name for the new branch and worktree

Example: `/worktree feature-test`

User provided: $ARGUMENTS

## Instructions

1. Parse the branch name from arguments
2. Always use the main branch worktree at `/Users/andrew/code/buttercut` as the source
3. Create a new git worktree at `../<branch-name>` with a new branch of the same name
4. Copy the entire `libraries/` directory from main: `/Users/andrew/code/buttercut/libraries/`
5. Copy the `media/` directory from main (if it exists): `/Users/andrew/code/buttercut/media/`
6. Run `mise trust` in the new worktree to trust the mise config
7. Run `bundle install` in the new worktree to install Ruby dependencies
8. Confirm success with the paths created

If the branch name is missing, ask the user to provide it: `/worktree <branch-name>`
