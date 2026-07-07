# Security policy

passdown is a set of skills and config templates — it does not run a
service, store credentials, or process user data of its own. Still, if you
find something security-relevant (a skill that could exfiltrate data, an
install path that writes outside its intended target, a manifest issue that
could be abused in a marketplace context) or spot private data (tokens,
paths, emails) accidentally committed to this repo, please report it
privately rather than opening a public issue.

**How to report:** open a
[private security advisory](https://github.com/vunm-io/passdown/security/advisories/new)
on GitHub. If that's unavailable, contact the maintainer through their
GitHub profile ([@vunm-io](https://github.com/vunm-io)).

Please include what you found, where (file/path or command), and how to
reproduce it if applicable. We'll acknowledge reports and follow up once
triaged — this is a small dogfooding project, so response time is best
effort, not SLA-backed.

## Supported versions

`main` / the latest tagged release only. There is no long-term support
branch at this stage.
