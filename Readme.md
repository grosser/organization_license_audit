Audit all licenses used by your github organization/user

Install
=======

```Bash
gem install organization_license_audit
```

Usage
=====

### Public repos
For yourself (git config github.user)
```Bash
organization-license-audit

parllel_tests
git clone git@github.com:grosser/parallel_tests.git --depth 1 --quiet
bundle --path vendor/bundle --quiet
license_finder --quiet
All gems are approved for use

evil_gem
git clone git@github.com:grosser/evil_gem.git --depth 1 --quiet
bundle --path vendor/bundle --quiet
license_finder --quiet
Dependencies that need approval:
evil_gem_dependency, 0.3.9, GPL

...

Failed:
https://github.com/grosser/parallel -- Michael Grosser <michael@grosser.it>
```

For someone else
```Bash
organization-license-audit --user grosser
```

Ignore gems (ignores repos that have a %{repo}.gemspec)
```Bash
organization-license-audit --ignore-gems
```

Silent:  only show vulnerable repos
```
organization-license-audit 2>/dev/null
```

CI: ignore old/unmaintained proejcts, unfixable/unimportant
```
organization-license-audit \
  --ignore https://github.com/xxx/a \
  --ignore https://github.com/xxx/b \
  --organization xxx \
  --token yyy
```

### CSV
just add `--csv` to get a nice csv report (`--csv '\t'` for tab separated -> paste into google docs)

### Private repos

```Bash
# create a token that has access to your repositories
curl -v -u your-user-name -X POST https://api.github.com/authorizations --data '{"scopes":["repo"]}'
enter your password -> TOKEN

organization-license-audit --user your-user --token TOKEN --organization your-organization
```

### Approving / tracking dependencies

To approve individual licenses or add dependencies take a look at [licence_finder](https://github.com/pivotal/LicenseFinder)

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/organization_license_audit.png)](https://travis-ci.org/grosser/organization_license_audit)
