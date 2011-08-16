# encoding: utf-8

require 'yaml'

class Hash
  #take keys of hash and transform those to a symbols
  def self.transform_keys_to_symbols(value)
    return value if not value.is_a?(Hash)
    hash = value.inject({}) { |memo, (k, v)| memo[k.to_sym] = Hash.transform_keys_to_symbols(v); memo }
    return hash
  end
end

module RottenEgg
  class AppSetting

    def self.parse!(config, is_file = false)

      setting_hash = is_file ? YAML::load_file(config) : YAML::load(config)
      setting      = Hash.transform_keys_to_symbols(setting_hash)

      setting.update(:name => "rotten_egg") unless setting[:name]

      raise "Scm is not in set." unless setting[:scm]
      # only support git and svn
      raise "Scm tools support [#{Scm::TOOLS.join("|")}]" unless Scm::TOOLS.include? setting[:scm][:tool]

      # Locate scm tool bin path
      scm_bin_path = Util.check_scm setting[:scm][:tool]
      setting[:scm].update(scm_bin_path)

      # Git repos branch default(master)
      setting[:scm].update(:branch => "master") unless setting[:scm][:branch] if setting[:scm][:tool] == "git"

      # Svn user and password
      if setting[:scm][:user] and setting[:scm][:password]
        setting[:scm].update(:authorize => true)
      else
        setting[:scm].update(:authorize => false)
      end if setting[:scm][:tool] == "svn"

      raise "Scm svn sanitize path prefix is missing" unless setting[:scm][:sanitize_path_prefix] if setting[:scm][:tool] == "svn"

      raise "Scm repository path is not in set." unless setting[:scm][:repository]

      setting[:scm][:repository] = Util.format_path(setting[:scm][:repository])

      # Although 'svn' commands support REPOS_URL, but in this case we need local repos
      raise "Scm repository path('#{setting[:scm][:repository]}') not exist, please check the given path exist." unless File.directory? setting[:scm][:repository]

      raise "Remote scm version file missing." unless setting[:scm][:remote_version_file]

      # FTP setting check
      raise "Ftp is not in set." unless setting[:ftp]

      #setting[:ftp].update(:use_sftp => %w(yes true).include?(setting[:ftp][:use_sftp]))
      setting[:ftp].update(:passive => %w(yes true).include?(setting[:ftp][:passive]))

      raise "Ftp host is not in set." unless setting[:ftp][:host]

      # Ftp default port 21
      setting[:ftp].update(:port => 21) unless setting[:ftp][:port]
      raise "Ftp user is not in set." unless setting[:ftp][:user]

      if setting[:ftp][:user] == "anonymous"
        setting[:ftp].update(:password => nil)
      else
        raise "Ftp password is not in set." unless setting[:ftp][:password]
      end

      setting
    end # - parse!

  end # - AppSetting

end # - RottenEgg