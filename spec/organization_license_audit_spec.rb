require "spec_helper"

describe OrganizationLicenseAudit do
  let(:public_token) { "--token 36a1b2a815b98d755528fa6e09b845965fe1e046" } # allows us to do more requests before getting rate limited

  it "has a VERSION" do
    OrganizationLicenseAudit::VERSION.should =~ /^[\.\da-z]+$/
  end

  context "CLI" do
    it "succeeds with approved" do
      result = audit("--user user-with-unpatched-apps --whitelist 'MIT,Ruby,Apache 2.0' #{public_token}")
      result.strip.should == "unpatched\ngit clone https://github.com/user-with-unpatched-apps/unpatched.git --depth 1 --quiet\nbundle --path vendor/bundle --quiet\nlicense_finder --quiet\nAll gems are approved for use"
    end

    it "fails with unapproved" do
      result = audit("--user user-with-unpatched-apps #{public_token}", :fail => true)
      result.strip.should include "Dependencies that need approval:"
      result.strip.should include "json, 1.5.3, ruby"
      result.strip.should include "Failed:\nMIT, ruby -- https://github.com/user-with-unpatched-apps/unpatched -- user-with-unpatched-apps <michael+unpatched@grosser.it>"
    end

    it "prints nice csv" do
      result = audit("--user user-with-unpatched-apps --csv #{public_token}", :fail => true)
      result.strip.should include "Dependencies that need approval:"
      result.strip.should include "json, 1.5.3, ruby"
      result.strip.should include "CSV:\nrepo,dependency,license\nhttps://github.com/user-with-unpatched-apps/unpatched,bundler,MIT\nhttps://github.com/user-with-unpatched-apps/unpatched,json,ruby"
    end

    it "prints nice csv with given separator" do
      result = audit("--user user-with-unpatched-apps --csv #{public_token} --csv '\\t'", :fail => true)
      result.strip.should include "Dependencies that need approval:"
      result.strip.should include "json, 1.5.3, ruby"
      result.strip.should include "CSV:\nrepo\tdependency\tlicense\nhttps://github.com/user-with-unpatched-apps/unpatched\tbundler\tMIT\nhttps://github.com/user-with-unpatched-apps/unpatched\tjson\truby"
    end

    it "ignores projects in --ignore" do
      result = audit("--user user-with-unpatched-apps --ignore https://github.com/user-with-unpatched-apps/unpatched 2>/dev/null #{public_token}", :keep_output => true)
      result.should == ""
    end

    it "shows --version" do
      audit("--version").should include(OrganizationLicenseAudit::VERSION)
    end

    it "shows --help" do
      audit("--help").should include("Audit all licenses")
    end

    context ".extract_error" do
      let(:result) do
        <<-OUT.gsub("          ", "")
          Dependencies that need approval:
          bundler, 1.5.0.rc.1, MIT
          json, 1.5.3, ruby
        OUT
      end

      it "extracts info" do
        OrganizationLicenseAudit.send(:extract_error, result).should == [["bundler", "MIT"], ["json", "ruby"]]
      end

      it "ignores empty lines" do
        OrganizationLicenseAudit.send(:extract_error, result+"\n   \n\n   \n").should == [["bundler", "MIT"], ["json", "ruby"]]
      end

      it "show stuff that is not a gem line" do
        expected = [["bundler", "MIT"], ["json", "ruby"], ["unparsable-line", "sdjfjhsdjs ss df ds"], ["unparsable-line", " there was an error here!!!  "]]
        OrganizationLicenseAudit.send(:extract_error, result+"\nsdjfjhsdjs ss df ds\n\n there was an error here!!!  \n").should == expected
      end
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
