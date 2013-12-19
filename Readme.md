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
parallel
No Gemfile.lock found

parllel_tests
license_finder
Licenses found: MIT, Apache

rails_example_app
license_finder
Licenses found: MIT, GPL

Failed:
rails_example_app - GPL
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

### Private repos

```Bash
# create a token that has access to your repositories
curl -v -u your-user-name -X POST https://api.github.com/authorizations --data '{"scopes":["repo"]}'
enter your password -> TOKEN

organization-license-audit --user your-user --token TOKEN --organization your-organization
```


Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/organization_license_audit.png)](https://travis-ci.org/grosser/organization_license_audit)
