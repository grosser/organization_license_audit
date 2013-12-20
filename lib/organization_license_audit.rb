require "organization_license_audit/version"
require "tmpdir"
require "organization_audit"

module OrganizationLicenseAudit
  BUNDLE_PATH = "vendor/bundle"

  class << self
    def run(options)
      bad = find_bad(options)
      # TODO nice summary like licenses / failed
      if bad.size == 0
        0
      else
        $stderr.puts "Failed:"
        puts bad
        1
      end
    end

    private

    def download_file(repo, file)
      return unless content = repo.content(file)
      File.write(file, content)
    end

    def find_bad(options)
      OrganizationAudit.all(options).select do |repo|
        next if options[:ignore_gems] and repo.gem?
        audit_repo(repo, options)
      end
    end

    def audit_repo(repo, options)
      bad = false
      $stderr.puts repo.name
      in_temp_dir do
        raise "Clone failed" unless sh("git clone #{repo.clone_url} --depth 1 --quiet")
        Dir.chdir repo.name do
          with_clean_env do
            bundled = File.exist?("Gemfile")
            raise "Failed to bundle" if bundled && !sh("bundle --path #{BUNDLE_PATH} --quiet")
            options[:whitelist].each do |license|
              raise "failed to approve #{license}" unless system("license_finder whitelist add '#{license}' >/dev/null")
            end
            bad = !sh("#{combined_gem_path if bundled}license_finder --quiet")
          end
        end
      end
      $stderr.puts ""
      bad
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
      $stderr.puts cmd.sub(/GEM_PATH=[^ ]+ /, "")
      IO.popen(cmd) do |pipe|
        while str = pipe.gets
          $stderr.puts str
        end
      end
      $?.success?
    end
  end
end
