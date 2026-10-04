We lint release fragments as parts of a page. Towncrier supplies their headings
when it folds them, so the push hook no longer demands a second page title in
each fragment. READMEs still need their titles, and fragments keep every other
Markdown structure check.
