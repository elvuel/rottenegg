# encoding: utf-8

require 'nokogiri'

module RottenEgg
  class Scm
    TOOLS = %w(git svn).freeze

    def self.get_changes(scm)
      case scm[:tool]
        when "git"
          Git.get_changes(scm)
        when "svn"
          Svn.get_changes(scm)
        else
          []
      end
    end

    class Git < Scm
      #Actions:  Added (A), Copied (C), Deleted (D), Modified (M), Renamed (R),Changed (T), Unmerged (U), Unknown (X)
      
      FILE_ACTIONS = %w(A D M).freeze

      CMD_PROC     = proc do |config, block|
        aim_branch = config[:branch]
        Dir.chdir(config[:repository]) do
          no_remote      = `git remote`.chomp.empty?
          branches       = `git branch`.chomp.split("\n")
          current_branch = branches.reject { |branch| branch[0].chr != "*" }.first.gsub("*", '').strip
          branches.collect! { |branch| branch.gsub('*', '').strip }
          if branches.include? aim_branch
            `git checkout #{aim_branch}` if current_branch != aim_branch
          else
            if no_remote
              raise RuntimeError, "fatal: no #{aim_branch} branch"
            else
              `git checkout -b #{aim_branch} origin/#{aim_branch}`
              branches       = `git branch`.chomp.split("\n")
              current_branch = branches.reject { |branch| branch[0].chr != "*" }.first.gsub("*", '').strip
              raise RuntimeError, "fatal: git checkout branch #{aim_branch} from origin/#{aim_branch}" if current_branch != aim_branch
            end
          end
          `git pull` unless no_remote

          if config[:first_commit]
            latest_commit = `git log -1 --format="%H"`.chomp
            config.update(:latest_commit => latest_commit)
          else
            commits = `git log --format="%H"`.chomp.split("\n")
            latest_commit, first_commit = commits.first, commits.last
            config.update(:latest_commit => latest_commit, :first_commit => first_commit)
          end
          block.call(config) if block
        end
      end

      def self.exec(config, &block)
        CMD_PROC.call(config, block)
      end

      def self.get_changes(scm)
        files = Git.exec(scm) do |cfg|
          if cfg[:remote_commit]
            if cfg[:remote_commit] == cfg[:latest_commit]
              []
            else
              log   = `git log --pretty=format: --name-status #{cfg[:remote_commit]}..#{cfg[:latest_commit]}`.chomp
              files = log.split("\n")
              files.delete ""
              files.reverse!

            end
          else
            log   = `git log --pretty=format: --name-status #{cfg[:first_commit]}..#{cfg[:latest_commit]}`.chomp
            files = log.split("\n")
            files.delete ""
            files.reverse!
          end
        end # - exec do block

        files.compact!

        unless files.empty?

          inject_result = files.inject({:file_final_status => {}, :file_names => []}) do |inj_for, item|
            action, filename = item.split("\t")
            filename                              = filename.chomp
            inj_for[:file_final_status][filename] = action.chomp.upcase
            inj_for[:file_names].delete filename if inj_for[:file_names].index(filename)
            inj_for[:file_names] << filename
            inj_for
          end

          file_hash, files_name = inject_result.delete(:file_final_status), inject_result.delete(:file_names)

          files      = files_name.collect do |filename|
            if file_hash[filename].nil?
              nil
            else
              if Git::FILE_ACTIONS.include?(file_hash[filename])
                {:action => file_hash[filename], :filename => filename, :status => :pending}
              else
                nil
              end
            end
          end.compact
        end # - unless files.empty?
        files
      end

    end # - Git class

    # currently no svn:externals support TODO?
    class Svn < Scm
      #Actions:  Added (A), Deleted (D), Modified (M), Replaced (R)

      FILE_ACTIONS = %w(A D M R).freeze

      CMD_PROC     = proc do |config, block|
        Dir.chdir(config[:repository]) do
          # SVN UP ERROR === TODO
          # svn: OPTIONS of 'http://svn.51hejia.com/51hejia/repos/brands/trunk': could not connect to server (http://svn.51hejia.com)
          svn_up = Svn.build_command("svn up", config)
          `#{svn_up}`
          if config[:first_commit]
            latest_commit = Svn.latest_revision(config)
            config.update(:latest_commit => latest_commit)
          else
            latest_commit, first_commit = Svn.latest_revision(config), Svn.first_revision(config)
            config.update(:latest_commit => latest_commit, :first_commit => first_commit)
          end
          block.call(config) if block
        end
      end

      def self.exec(config, &block)
        CMD_PROC.call(config, block)
      end

      def self.build_command(cmd, config)
        cmd << " --username=#{config[:user]} --password=#{config[:password]} --no-auth-cache" if config[:authorize]
        cmd
      end

      def self.first_revision(config={})
        cmd    = build_command("svn log -q -r 0:HEAD --limit=1", config)
        result = `#{cmd}`.chomp!
        lines  = result.split("\n").reverse
        line   = lines[1]
        line.nil? ? '' : line.scan(/\Ar\d+/).first.to_s.gsub("r", '')
      end

      def self.latest_revision(config={})
        cmd    = build_command("svn info -r HEAD", config)
        result = `#{cmd}`.chomp!
        lines  = result.split("\n").reverse
        line   = lines[1]
        line.nil? ? '' : line.scan(/\d+/).first.to_s
      end

      def self.parse_log(xml, sanitize_paths)
        paths = sanitize_paths.split("|")
        xml_doc         = Nokogiri::XML(xml)
        files           = xml_doc.xpath("//path").collect do |node|
          if node["kind"] == "file"
            file_path = node.text.to_s
            file_path = file_path.gsub(%r(\A#{paths.join("|")}), '').strip
            file_path.empty? ? nil : "#{node["action"]}\t#{file_path}"
          else
            nil
          end
        end.compact
        files
      end

      def self.get_changes(scm)
        files = Svn.exec(scm) do |cfg|
          if cfg[:remote_commit]
            if cfg[:remote_commit] == cfg[:latest_commit]
              []
            else
              cmd   = Svn.build_command("svn log -v -r #{cfg[:remote_commit]}:#{cfg[:latest_commit]} --xml", cfg)
              log   = `#{cmd}`.chomp
              Svn.parse_log(log, cfg[:sanitize_path_prefix])
            end
          else
            cmd   = Svn.build_command("svn log -v -r #{cfg[:first_commit]}:#{cfg[:latest_commit]} --xml", cfg)
            log   = `#{cmd}`.chomp
            Svn.parse_log(log, cfg[:sanitize_path_prefix])
          end
        end # - exec do block

        files.compact!

        unless files.empty?

          inject_result = files.inject({:file_final_status => {}, :file_names => []}) do |inj_for, item|
            action, filename = item.split("\t")
            filename                              = filename.chomp
            inj_for[:file_final_status][filename] = action.chomp.upcase
            inj_for[:file_names].delete filename if inj_for[:file_names].index(filename)
            inj_for[:file_names] << filename
            inj_for
          end

          file_hash, files_name = inject_result.delete(:file_final_status), inject_result.delete(:file_names)

          files      = files_name.collect do |filename|
            if file_hash[filename].nil?
              nil
            else
              if Svn::FILE_ACTIONS.include?(file_hash[filename])
                # replace 'Replaced(R)' to 'Modified(M)'
                {:action => (file_hash[filename] == "R" ? "M" : file_hash[filename]), :filename => filename, :status => :pending}
              else
                nil
              end
            end
          end.compact
        end # - unless files.empty?

        files
      end

    end

  end # - Scm class
end # - RottenEgg module