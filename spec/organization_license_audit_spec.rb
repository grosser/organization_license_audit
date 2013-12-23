require "spec_helper"

describe OrganizationLicenseAudit do
  let(:public_token) { "--token 36a1b2a815b98d755528fa6e09b845965fe1e046" } # allows us to do more requests before getting rate limited

  it "has a VERSION" do
    OrganizationLicenseAudit::VERSION.should =~ /^[\.\da-z]+$/
  end

  context ".use_cache_dir_to_bundle" do
    def call(*args)
      OrganizationLicenseAudit.send(:use_cache_dir_to_bundle, *args)
    end

    let(:cache) { File.expand_path("cache") }

    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir, &example) } }
    before { FileUtils.mkdir(cache) }

    it "symlinks default cache path" do
      call(cache)
      File.directory?("#{cache}/default").should == true
      File.directory?("vendor").should == true
      File.realpath("vendor/bundle").should == "#{cache}/default"
    end

    it "symlinks .ruby-version cache path" do
      File.write(".ruby-version", "1.2.3")
      call(cache)
      File.directory?("#{cache}/1.2.3").should == true
      File.directory?("vendor").should == true
      File.realpath("vendor/bundle").should == "#{cache}/1.2.3"
    end

    it "symlinks .rvmrc cache path" do
      File.write(".rvmrc", "rvm use 1.2.3")
      call(cache)
      File.directory?("#{cache}/rvm_use_1.2.3").should == true
      File.directory?("vendor").should == true
      File.realpath("vendor/bundle").should == "#{cache}/rvm_use_1.2.3"
    end
  end

  context ".audit_project" do
    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir, &example) } }
    before { $stderr.stub(:puts) }

    def call(*args)
      OrganizationLicenseAudit.send(:audit_project, *args)
    end

    context "a project with packages.json" do
      before do
        File.write("Readme", "XXX") # silence npm warnings
        File.write("package.json", '{"dependencies": { "sigmund": "1.0.0" }, "description": "XX", "repository": "XX" }')
      end

      it "runs npm" do
        call("xxx", :whitelist => []).first.should == false
        call("xxx", :whitelist => ["BSD"]).first.should == true
      end

      it "ignores npm with --without npm" do
        call("xxx", :whitelist => [], :without => ["npm"]).first.should == true
      end
    end

    context "a project with Gemfile" do
      before do
        FileUtils.mkdir("xxx")
        File.write("Gemfile", "source 'https://rubygems.org'\ngem 'rake'")
      end

      it "runs bundler" do
        call(File.expand_path("xxx"), :whitelist => []).first.should == false
        call(File.expand_path("xxx"), :whitelist => ["MIT"]).first.should == true
      end

      it "ignores bundler with --without bundler" do
        call(File.expand_path("xxx"), :whitelist => [], :without => ["bundler"]).first.should == true
      end
    end
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

    it "succeeds when all unapproved are in without" do
      result = audit("--user user-with-unpatched-apps --without bundler #{public_token}")
      result.strip.should == "unpatched\ngit clone https://github.com/user-with-unpatched-apps/unpatched.git --depth 1 --quiet\nlicense_finder --quiet\nAll gems are approved for use"
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
