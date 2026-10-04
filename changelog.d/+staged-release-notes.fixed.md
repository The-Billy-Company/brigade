We commit Towncrier's staged changelog and fragment removals onto the release
PR. The fold now compares both staged and unstaged changes with HEAD, so staged
release notes cannot disappear behind a successful "nothing new" check.
