A filtered run that selects nothing now says which lever emptied the set.

brigade fails such a run on purpose — a filter that matches no test is a typo,
and reporting it as a green suite that tested exactly zero things is the failure
mode the runner exists to prevent. But it counted survivors *after* applying the
skip and then blamed the filter for the number, so `BRIGADE_FILTER='even'
BRIGADE_SKIP='even'` reported `matched none of the 12 tests` when the filter had
in fact matched six and the skip had stood all six aside. The reader goes and
stares at the wrong variable.

Filter matches are counted separately from post-skip survivors now, and the two
emptinesses have their own message: `matched none of the N tests` when the
filter found nothing, and `matched M of the N tests, and BRIGADE_SKIP='…' stood
every one of them aside` when it found something the skip then consumed. Both
still exit 1 from every shard, so the build fails whichever one the runner
reaches first.

Found by writing the adverse case rather than by hitting it: the behavior was
inherited unchanged by all three copies of the runner that existed before this
package did.
