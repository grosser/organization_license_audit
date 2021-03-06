require "organization_license_audit/version"
require "tmpdir"
require "organization_audit"
require "shellwords"
require "open3"

module OrganizationLicenseAudit
  BUNDLE_PATH = "vendor/bundle"
  RESULT_LINE = /(^[a-z_\d\.-]+), ([^,]+), (.+)/i
  APPROVAL_HEADING = "Dependencies that need approval"
  PACKAGE_FILES = {
    :bundler => "Gemfile",
    :npm     => "package.json",
    :bower   => "bower.json"
  }

  class << self
    def run(options)
      bad = find_bad(options)
      if bad.any?
        $stderr.puts "Failed:"

        errors = bad.map { |repo, output| [repo, extract_error(output)] }

        errors.each do |repo, unapproved|
          puts "#{describe_error(unapproved)} -- #{repo}"
        end

        if options[:csv]
          puts
          puts "CSV:"
          puts csv(errors, options[:csv])
        end

        1
      else
        0
      end
    end

    private

    def describe_error(unapproved)
      if unapproved
        unapproved.map(&:last).flatten.uniq.sort.join(", ")
      else
        "Unknown error"
      end
    end

    def csv(errors, col_sep)
      require "csv"
      CSV.generate(:col_sep => col_sep) do |csv|
        csv << ["repo", "dependency", "license"]
        errors.each do |repo, errors|
          if errors
            errors.each do |gem, license|
              csv << [repo.url, gem, license]
            end
          else
            csv << [repo.url, "Unknown error"]
          end
        end
      end
    end

    def extract_error(output)
      if output.to_s.include?(APPROVAL_HEADING)
        output = output.split("\n")
        output.reject! { |l| l.include?(APPROVAL_HEADING) || l.strip == "" }
        output.map do |line|
          if line =~ RESULT_LINE
            [$1, $3]
          else
            ["unparsable-line", line] # do not swallow the unknown or we might hide an error
          end
        end
      end
    end

    def download_file(repo, file)
      begin
        content = repo.content(file)
      rescue StandardError => e
        puts "Error downloading #{file}: #{e.to_s}"
        content = repo.content(file)
      end
      return unless content
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, content)
    end

    def find_bad(options)
      Dir.mktmpdir do |bundle_cache_dir|
        repos = OrganizationAudit.all(options)
        repos.select! { |r| options[:debug].include?(r.name) } if options[:debug]
        select_parallel_group!(repos)
        repos.map do |repo|
          next if options[:ignore_gems] && repo.gem?
          success, output = audit_repo(repo, bundle_cache_dir, options)
          $stderr.puts ""
          [repo, output] unless success
        end.compact
      end
    end

    def audit_repo(repo, bundle_cache_dir, options)
      $stderr.puts repo.name
      in_temp_dir do
        if repo.gem?
          # download everything since gemspecs can require stuff (also gems are mostly small...)
          raise "Clone failed" unless sh("git clone #{repo.clone_url} --depth 1 --quiet .").first
        else
          # download only the files we need to save time on giant projects
          needed_files(repo, options).each { |path| download_file(repo, path) }
        end
        audit_project(bundle_cache_dir, options)
      end
    rescue Exception => e
      raise if e.is_a?(Interrupt) # user interrupted
      $stderr.puts "Error auditing #{repo.name} (#{e})"
      puts e.backtrace if options[:debug]
      false
    end

    def needed_files(repo, options)
      list = repo.file_list
      list += repo.file_list("config") if repo.directory?("config")
      supported = ["config/license_finder.yml"]
      supported << "Gemfile.lock" if wanted?(:bundler, options)
      supported.concat PACKAGE_FILES.map { |t,f| f if wanted?(t, options) }.compact
      supported & list
    end

    def audit_project(bundle_cache_dir, options={})
      with_clean_env do
        bundled = prepare_bundler bundle_cache_dir, options
        prepare_npm options
        prepare_bower options
        whitelist_licences options[:whitelist]
        approve_dependencies options[:approve]

        sh "#{combined_gem_path if bundled}license_finder --quiet"
      end
    end

    def approve_dependencies(dependencies)
      return unless dependencies and dependencies.any?

      # do not keep connection to Sequel around or next run fails
      # reproducible with 2 repos --debug repo1,repo2 --approve xxx
      # even disconnect + connect does not help since it never re-runs
      # migrations, and then fails to run migrations properly
      fork do
        require 'license_finder'
        require 'license_finder/tables'
        require 'license_finder/tables/dependency'
        require 'license_finder/tables/license_alias'
        require 'license_finder/tables/approval'

        dependencies.each do |name|
          dependency = LicenseFinder::Dependency.new(name: name, version: ">=0")
          dependency.license = LicenseFinder::LicenseAlias.create(name: "other")
          dependency.approval = LicenseFinder::Approval.create(:state => true)
          dependency.save
        end
      end
      Process.waitall # wait for fork to finish
    end

    def whitelist_licences(licenses)
      return unless licenses and licenses.any?
      licenses = licenses.map { |l| Shellwords.escape(l) }.join(" ")
      unless system("license_finder whitelist add #{licenses} >/dev/null")
        raise "failed to approve #{licenses}"
      end
    end

    def prepare_bundler(bundle_cache_dir, options)
      with_or_without :bundler, options do
        use_cache_dir_to_bundle(bundle_cache_dir)
        raise "Failed to bundle" unless sh_with_retry("bundle --path #{BUNDLE_PATH} --quiet 2>&1", "Gem::RemoteFetcher::FetchError").first
        true
      end
    end

    def prepare_npm(options)
      with_or_without :npm, options do
        sh "npm install --quiet"
      end
    end

    def prepare_bower(options)
      with_or_without :bower, options
    end

    def use_cache_dir_to_bundle(cache_dir)
      cache_dir = File.join(cache_dir, ruby_cache)
      FileUtils.mkdir_p cache_dir
      FileUtils.mkdir_p File.dirname(BUNDLE_PATH)
      FileUtils.symlink cache_dir, BUNDLE_PATH
    end

    # use one directory per ruby-version (not the same for jruby or different patch releases)
    def ruby_cache
      ruby_version = [".ruby-version", ".rvmrc"].detect { |f| File.exist?(f) }
      ruby_version = File.read(ruby_version) if ruby_version
      ruby_version ||= "default"
      ruby_version.gsub!(/[^a-z\d\.]/, "_") # .rvmrc might include weirdness...
      ruby_version
    end

    # license_finder needs to find all gems in the target repo, which fails if their path is not in the GEM_PATH
    # so we have to add the gems in vendor/bundle to the gems currently available from this bundle
    def combined_gem_path
      "GEM_PATH=#{`gem env path`.strip}:#{BUNDLE_PATH}/ruby/* "
    end

    def in_temp_dir(&block)
      Dir.mktmpdir { |dir| Dir.chdir(dir, &block) }
    end

    def with_clean_env(&block)
      if defined?(Bundler)
        Bundler.with_clean_env(&block)
      else
        yield
      end
    end

    # http://grosser.it/2010/12/11/sh-without-rake
    def sh(cmd)
      output = ""
      $stderr.puts cmd.sub(/GEM_PATH=[^ ]+ /, "")
      IO.popen(cmd) do |pipe|
        while str = pipe.gets
          output << str
          $stderr.puts str
        end
      end
      [$?.success?, output]
    end

    def sh_with_retry(cmd, retry_on)
      status = false
      result = ""
      3.times do |i|
        $stderr.puts "Retrying failed command" if i > 0
        status, current = sh(cmd)
        result << current
        return status, result if status
        break unless current.include?(retry_on)
      end
      return status, result
    end

    def select_parallel_group!(repos)
      return unless group = ENV["OLA_GROUP"]
      group, groups = group.split("/").map(&:to_i)
      repos.each_with_index do |repo, i|
        repos[i] = nil unless (i % groups) + 1 == group
      end
      repos.compact!
    end

    def wanted?(thing, options)
      not (options[:without] || []).include?(thing.to_s)
    end

    def with_or_without(thing, options)
      file = PACKAGE_FILES.fetch(thing)
      return unless File.exist?(file)
      if wanted?(thing, options)
        yield if block_given?
      else
        File.unlink(file)
      end
    end
  end
end
