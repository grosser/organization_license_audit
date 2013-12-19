require "spec_helper"

describe OrganizationLicenseAudit do
  let(:public_token) { "--token 36a1b2a815b98d755528fa6e09b845965fe1e046" } # allows us to do more requests before getting rate limited

  it "has a VERSION" do
    OrganizationLicenseAudit::VERSION.should =~ /^[\.\da-z]+$/
  end

  context "CLI" do
    it "succeeds with approved" do
      result = audit("--user user-with-unpatched-apps --whitelist MIT,Ruby #{public_token}")
      result.strip.should == "unpatched\ngit clone git@github.com:user-with-unpatched-apps/unpatched.git --depth 1 --quiet\nbundle --path vendor/bundle --quiet\nlicense_finder --quiet\nAll gems are approved for use"
    end

    it "fails with unapproved" do
      result = audit("--user user-with-unpatched-apps #{public_token}", :fail => true)
      result.strip.should include "Dependencies that need approval:"
      result.strip.should include "json, 1.5.3, ruby"
      result.strip.should include "Failed:\nhttps://github.com/user-with-unpatched-apps/unpatched -- user-with-unpatched-apps <michael+unpatched@grosser.it>"
    end

    it "ignores projects in --ignore" do
      result = audit("--user user-with-unpatched-apps --ignore https://github.com/user-with-unpatched-apps/unpatched 2>/dev/null", :keep_output => true)
      result.should == ""
    end

    it "shows --version" do
      audit("--version").should include(OrganizationLicenseAudit::VERSION)
    end

    it "shows --help" do
      audit("--help").should include("Audit all licenses")
    end

    def audit(command, options={})
      sh("bin/organization-license-audit #{command}", options)
    end

    def sh(command, options={})
      result = `#{command} #{"2>&1" unless options[:keep_output]}`
      raise "FAILED #{command}\n#{result}" if $?.success? == !!options[:fail]
      normalize(result)
    end

    def normalize(string)
      string.gsub(/\e\[\d+m/, "").gsub(/Warning: Permanently added.*/, "").gsub(/\n+/, "\n")
    end
  end
end
