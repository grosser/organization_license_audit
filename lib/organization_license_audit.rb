require "organization_license_audit/version"
require "tmpdir"
require "bundler/organization_audit/repo"

module OrganizationLicenseAudit
  class << self
    def run(options)
      bad = find_bad(options)
      if bad.size == 0
        0
      else
        $stderr.puts "Bad licenses:"
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
      Bundler::OrganizationAudit::Repo.all(options).select do |repo|
        next if (options[:ignore] || []).include? repo.url
        audit_repo(repo, options)
      end
    end

    def audit_repo(repo, options)
      success = false
      $stderr.puts repo.project
      in_temp_dir do
        if options[:ignore_gems] && repo.gem?
          $stderr.puts "Ignored because it's a gem"
        else
          raise "Clone failed" unless sh("git clone #{repo.clone_url} --depth 1 --quiet")
          Dir.chdir repo.project do
            with_clean_env do
              raise "Failed to bundle" unless system("([ ! -e Gemfile ] || bundle --path vendor/bundle --quiet)")
              options[:whitelist].each do |license|
                raise "failed to approve #{license}" unless system("license_finder whitelist add #{license} >/dev/null")
              end
              success = !sh("license_finder --quiet")
            end
          end
        end
      end
      $stderr.puts ""
      success
    rescue Exception => e
      $stderr.puts "Error auditing #{repo.project} (#{e})"
    end

    def in_temp_dir(&block)
      Dir.mktmpdir { |dir| Dir.chdir(dir, &block) }
    end

    def with_clean_env(&block)
      if Bundler.respond_to?(:with_clean_env)
        Bundler.with_clean_env(&block)
      else
        yield
      end
    end

    # http://grosser.it/2010/12/11/sh-without-rake
    def sh(cmd)
      $stderr.puts cmd
      IO.popen(cmd) do |pipe|
        while str = pipe.gets
          $stderr.puts str
        end
      end
      $?.success?
    end
  end
end

Bundler::OrganizationAudit::Repo.class_eval do
  def clone_url
    url.sub("https://", "git@").sub("/", ":") + ".git"
  end
end
