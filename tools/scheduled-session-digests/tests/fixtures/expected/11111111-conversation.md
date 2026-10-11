[USER]
Please add a retry to the upload step.

[ASSISTANT]
I will add a retry.

[QUESTION]
How many retries?
Options:
- Three: Matches the other steps.
- Five

[QUESTION]
Which steps?
Options:
- Upload: The flaky one.
- Download: Rarely fails.

[ANSWER]
Q: How many retries?
A: Three
Notes: Keep it simple.
Q: Which steps?
A: Upload, Download

[USER REJECTED Bash]

[USER]
Do not delete the build folder, it holds the cache.

[INTERRUPTED]

[INTERRUPTED]

[USER]
git status

[USER]
/clear

[USER]
Use exponential backoff.

[USER]
Also log each retry.

[USER]
See the screenshot.

[ASSISTANT]
Done.

