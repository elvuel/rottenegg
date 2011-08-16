# encoding: utf-8

require 'rbconfig'
require 'thread'
require 'net/ftp'
#require 'net/sftp'
require 'fileutils'

module RottenEgg

  module Util

    MS_ECHO_PATH      = "echo %PATH%".freeze
    NX_ECHO_PATH      = "echo $PATH".freeze
    MS_BIN_TYPE       = ["", ".exe", ".cmd"].freeze
    NX_BIN_TYPE       = [].freeze
    MS_PATH_DELIMITER = ";".freeze
    NX_PATH_DELIMITER = ":".freeze

    class FtpTool #:nodoc: internal use only

      attr_accessor :verbose
      attr_reader :server, :port, :user, :password

      def initialize(server, port, user, password, options={})
        @server     = server
        @port       = port
        @user       = user
        @password   = password
        @connection = nil
        @verbose    = options[:verbose] || false
        @passive    = options[:passive] || false
        @msg_logger = options[:msg_logger]
        @lock       = Mutex.new
      end

      def pull_files(local_path, file_list)
        @lock.synchronize do
          return {} unless connect!
          file_list = [file_list.to_s] unless file_list.is_a? Array
          file_list.uniq!
          result = file_list.inject({}) do |hash, f|
            status  = if file_exist?(f)
                        local_dir = File.join(local_path, File.dirname(f))
                        FileUtils.mkdir_p local_dir unless File.exist?(local_dir)
                        local_file        = File.join(local_dir, File.basename(f))
                        origin_local_file = local_file + ".origin"

                        if File.exist? local_file
                          FileUtils.mv local_file, origin_local_file

                          # still exist!  FileUtils # rename_cannot_overwrite_file?
                          FileUtils.rm local_file if File.exist? local_file
                        end
                        pull_result = pull_file f, File.join(local_dir, File.basename(f))
                        if pull_result
                          FileUtils.rm origin_local_file if File.exist?(origin_local_file)
                          :success
                        else
                          FileUtils.mv origin_local_file, local_file
                          :failure
                        end
                      else
                        :not_exist # file not exist !
                      end # - file_exist? f
            hash[f] = status
            hash
          end # - file_list inject
          close!
          result
        end
      end

      # download version file
      def download_version_file(local_path, file)
        result = pull_files local_path, file
        if result.empty?
          log "ftp connect failure"
          :ftp_connect_failure
        else
          case result[file]
            when :success
              :success
            when :failure
              log 'download remove version file failed'
              :failure
            when :not_exist
              :initial
          end
        end
      end

      #
      # Pull a supplied list of files from the remote ftp path into the local path
      #
      def apply_changes(local_path, file_lists)
        @lock.synchronize do
          return false if file_lists.empty? or !connect!
          result = true
          file_lists.each do |item|
            file = item[:filename]
            action = item[:action]
            item_index = file_lists.index(item)
            file_dir    = File.dirname(file)
            case action
              when "A", "M"
                pull_status = push_file "#{local_path}#{file}", file_dir, file
                if pull_status
                  status = :success
                else
                  status = :failed
                  result = pull_status
                end
                file_lists[item_index].update(:status => status)
              when "D"
                file_dir = "/" if file_dir == "." or file_dir == ""
                if file_exist?(file)
                  if delete_file(file)
                    delete_dir(file_dir) if dir_empty?(file_dir) #remove remote dir
                  end
                  file_lists[item_index].update(:status => :success)
                else # no remote file set true
                  file_lists[item_index].update(:status => :success)
                end
            end
          end
          close!
          result
        end
      end

      # upload version file
      def update_version_file(local_file, remote_file=File.basename(local_file))
        @lock.synchronize do
          return false unless connect!
          file_dir = File.dirname(remote_file)
          result = push_file "#{local_file}", file_dir, remote_file
          close!
          result
        end
      end

      private
      # open connection
      def connect!
        begin
          Timeout.timeout(15) do
            log "Connection to #{@server}..."
            @connection ||= Net::FTP.new()
            @connection.passive = @passive
            @connection.connect(@server, @port)
            @connection.login(@user, @password)
            log "Opened connection to #{@server}"
            return true
          end
        rescue Timeout::Error
          log "Open connection to #{@server}:#{@port} time out"
          return false
        rescue Net::FTPConnectionError
          @connection = nil
          log "Connect to #{@server} connection error"
          return false
        rescue Errno::ECONNREFUSED
          log "Connect to #{@server} refused"
          return false
        rescue Net::FTPPermError
          log "Connect to #{@server} permission denied"
          return false
        rescue
          log "Connect to #{@server} error"
          return false
        end
      end

      # close connection
      def close!
        begin
          @connection.close
          @connection = nil
          log "Closed Connection to #{@server}"
        rescue

        end
      end

      # check remote directory exist?
      def dir_exist?(dir)
        return false if server_down?

        status = begin
          @connection.chdir(dir)
          true
        rescue
          log "Remote directory #{dir} not exist"
          false
        end
        @connection.chdir('/') if status
        status
      end

      # check remote dir empty?
      def dir_empty?(dir)
        return false if server_down?

        if dir_exist?(dir)
          files = @connection.nlst(dir)
          files.any?
        else
          true
        end
      end

      # create directory
      def create_dir(dir)
        return false if server_down?

        begin
          @connection.mkdir(dir)
          true
        rescue
          log "Create remote directory #{dir}"
          false
        end
      end

      # create directory
      def delete_dir(dir)
        return false if server_down?

        begin
          @connection.rmdir(dir)
          true
        rescue
          log "Remote remote directory #{dir} error"
          false
        end
      end

      # create directories
      def create_dirs(path, base = '/')
        return false if server_down?

        base = '' if base == '/'
        parent    = base
        path_list = path.split("/")
        path_list.each do |item|
          parent = "#{parent}/#{item}"
          unless dir_exist?(parent)
            return false unless create_dir(parent)
          end
        end
        true
      end

      # download single file
      def pull_file(remote_file, local_file)
        return false if server_down?

        begin
          log "Pulling #{remote_file} to #{local_file}..."
          @connection.get remote_file, local_file
          log "Pulled #{remote_file} to #{local_file}..."
          true
        rescue
          log "Pull #{remote_file} error reading..."
          false
        end
      end

      # upload single file
      def push_file(local_file, remote_dir = "/", remote_file=File.basename(local_file))
        return false if server_down?

        unless File.exist?(local_file)
          log "local file #{local_file} not exist"
          return true# local file not exist then return true not false
        end

        remote_dir = "/" if remote_dir == "." or remote_dir == ""
        unless dir_exist?(remote_dir)
          return false unless create_dirs(remote_dir)
        end

        begin
          @connection.chdir(remote_dir) unless remote_dir == "/"
          log "Pushing #{local_file} to remote..."
          @connection.put local_file, File.basename(remote_file)
          @connection.chdir("/")
          log "Pushed #{local_file} to remote"
          true
        rescue
          @connection.chdir("/")
          log "Push #{local_file} to remote error"
          false
        end
      end

      # delete single file
      def delete_file(remote_file)
        return false if server_down?

        begin
          @connection.delete remote_file
          log "Remote file #{local_file} successfully deleted"
          true
        rescue
          log "Delete remote file: #{remote_file} error"
          false
        end
      end

      # check remote file exist?
      def file_exist?(file_path)
        return false if server_down?

        path, file_name = File.dirname(file_path), File.basename(file_path)
        if dir_exist?(path)
          files = @connection.nlst(path)
          if files.include?(file_name)
            true
          else
            log "Remote file #{file_path} not exist"
            false
          end
        else
          log "Remote file #{file_path} not exist"
          false
        end
      end

      def server_down?
        begin
          @connection.chdir("/")
          false
        rescue
          log "<。)#)))≦ ~~~~~ Remote ftp server is down!"
          true
        end
      end

      # log message
      def log(msg)
        @msg_logger.add(msg) if @msg_logger
        puts msg if @verbose
      end
    end

    module_function

    def mswin?
      Config::CONFIG['target_os'] =~ /mswin32|mingw32/ ? true : false
    end

    def format_path(path)
      path = path.chomp.gsub("\\", "/") if mswin?
      path = "#{path}/" if path[-1].chr != "/"
      path
    end

    def check_scm(scm)
      #send "check_#{scm}".to_sym
      # not by scm --version
      if mswin?
        paths    = `#{MS_ECHO_PATH}`.split(MS_PATH_DELIMITER)
        bin_path = MS_BIN_TYPE.inject([]) do |ary, type|
          ary << paths.reject { |path| !File.exist?("#{path.chomp.gsub("\\", "/")}/#{scm}#{type}") }
        end.collect { |path| path.any? ? path.first : nil }.compact.first.to_s

        raise "Please install #{scm}." if bin_path.empty?
        {:bin_path => bin_path}
      else
        bin_path = `which #{scm}`.chomp
        raise "Please install #{scm}." if bin_path.empty?
        {:bin_path => bin_path}
      end
    end # - check_scm


  end # - Util

end # - RottenEgg