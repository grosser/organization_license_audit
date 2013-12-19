require "spec_helper"

describe OrganizationLicenseAudit do
  it "has a VERSION" do
    OrganizationLicenseAudit::VERSION.should =~ /^[\.\da-z]+$/
  end

  context "CLI" do
    it "succeeds with approved" do
      result = audit("--user user-with-unpatched-apps --approve MIT,Ruby")
      result.should include "unpatched\nbundle-audit\nName: json\nVersion: 1.5.3" # Individual vulnerabilities
      result.should include "Vulnerable:\nhttps://github.com/user-with-unpatched-apps/unpatched" # Summary
    end

    it "fails with unapproved" do
      result = audit("--user user-with-unpatched-apps", :fail => true)
      result.should include "unpatched\nbundle-audit\nName: json\nVersion: 1.5.3" # Individual vulnerabilities
      result.should include "Vulnerable:\nhttps://github.com/user-with-unpatched-apps/unpatched" # Summary
    end

    it "only shows failed projects on stdout" do
      result = audit("--user user-with-unpatched-apps 2>/dev/null", :fail => true, :keep_output => true)
      result.should == "https://github.com/user-with-unpatched-apps/unpatched -- user-with-unpatched-apps <michael+unpatched@grosser.it>\n"
    end

    it "ignores projects in --ignore" do
      result = audit("--user user-with-unpatched-apps --ignore https://github.com/user-with-unpatched-apps/unpatched 2>/dev/null", :keep_output => true)
      result.should == ""
    end

    it "shows --version" do
      audit("--version").should include(OrganizationLicenseAudit::VERSION)
    end

    it "shows --help" do
      audit("--help").should include("Audit all Gemfiles")
    end

    def audit(command, options={})
      sh("bin/bundle-organization-audit #{command}", options)
    end

    def sh(command, options={})
      result = `#{command} #{"2>&1" unless options[:keep_output]}`
      raise "FAILED #{command}\n#{result}" if $?.success? == !!options[:fail]
      decolorize(result)
    end
  end
end
