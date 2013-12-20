require "organization_license_audit/version"
require "tmpdir"
require "organization_audit"

module OrganizationLicenseAudit
  BUNDLE_PATH = "vendor/bundle"
  RESULT_LINE = /(^[a-z_\d-]+), ([^,]+), (.+)/
  APPROVAL_HEADING = "Dependencies that need approval"

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
          puts csv(errors)
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

    def csv(errors)
      require "csv"
      CSV.generate do |csv|
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
      if output.include?(APPROVAL_HEADING)
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
      return unless content = repo.content(file)
      File.write(file, content)
    end

    def find_bad(options)
      OrganizationAudit.all(options).map do |repo|
        next if options[:ignore_gems] and repo.gem?
        success, output = audit_repo(repo, options)
        $stderr.puts ""
        [repo, output] unless success
      end.compact
    end

    def audit_repo(repo, options)
      $stderr.puts repo.name
      in_temp_dir do
        raise "Clone failed" unless sh("git clone #{repo.clone_url} --depth 1 --quiet").first
        Dir.chdir repo.name do
          with_clean_env do
            bundled = File.exist?("Gemfile")
            raise "Failed to bundle" if bundled && !sh("bundle --path #{BUNDLE_PATH} --quiet").first
            options[:whitelist].each do |license|
              raise "failed to approve #{license}" unless system("license_finder whitelist add '#{license}' >/dev/null")
            end
            sh("#{combined_gem_path if bundled}license_finder --quiet")
          end
        end
      end
    rescue Exception => e
      raise if e.is_a?(Interrupt) # user interrupted
      $stderr.puts "Error auditing #{repo.name} (#{e})"
      true
    end

    # license_finder loads all gems in the target repo, which fails if they are not available in the current ruby installation
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
  end
end
