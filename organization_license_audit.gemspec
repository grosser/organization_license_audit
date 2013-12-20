$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
name = "organization_license_audit"
require "#{name.gsub("-","/")}/version"

Gem::Specification.new name, OrganizationLicenseAudit::VERSION do |s|
  s.summary = "Audit all licenses used by your github organization/user"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "http://github.com/grosser/#{name}"
  s.files = `git ls-files lib/ bin/ MIT-LICENSE`.split("\n")
  s.license = "MIT"
  cert = File.expand_path("~/.ssh/gem-private-key-grosser.pem")
  if File.exist?(cert)
    s.signing_key = cert
    s.cert_chain = ["gem-public_cert.pem"]
  end
  s.executables = ["organization-license-audit"]
  s.add_runtime_dependency "organization_audit"
  s.add_runtime_dependency "license_finder"
end
