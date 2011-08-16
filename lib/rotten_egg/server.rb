# encoding: utf-8

require 'optparse'
require 'yaml'
require 'fileutils'

module RottenEgg
  class Server

    # server start up options
    class Options
      def parse!(args)
        options    = {}
        opt_parser = OptionParser.new("", 40, '  ') do |opts|
          opts.banner = "Usage: rotten_egg options"

          opts.separator ""
          opts.separator "options:"

#          lineno = 1
#          opts.on("-e", "--eval LINE", "evaluate a LINE of code") { |line|
#            eval line, TOPLEVEL_BINDING, "-e", lineno
#            lineno += 1
#          }

#          opts.on("-d", "--debug", "set debugging flags (set $DEBUG to true)") {
#            options[:debug] = true
#          }
#
#          opts.on("-w", "--warn", "turn warnings on for your script") {
#            options[:warn] = true
#          }

#          opts.on("-s", "--server SERVER", "serve using SERVER (thin)") { |s|
#            options[:server] = s
#          }

          opts.on("-o", "--host HOST", "listen on HOST (default: 0.0.0.0)") { |host|
            options[:host] = host
          }

          opts.on("-p", "--port PORT", "use PORT (default: 17420)") { |port|
            options[:port] = port
          }

          opts.on("-e", "--env ENVIRONMENT", "use ENVIRONMENT (default: development)") { |e|
            options[:environment] = e.to_sym
          }

          opts.on("-C", "--config FILE", "app config file (default: rotten_egg.yml)") { |c|
            options[:config] = c
          }

          opts.on("-A", "--auth FILE", "app auth file (if nil default auth: user:'rotten' password:'egg')") { |a|
            options[:auth_file] = a
          }

          opts.on("-W", "--working_directory DIRECTORY", "app working directory") { |w|
            options[:working_directory] = w
          }

          opts.on("-m", "--paging_size SIZE", "max perpage for paginate") { |ps|
            options[:paging_size] = ps
          }

          opts.separator ""
          opts.separator "Daemonize options:"

          opts.on("-D", "--daemonize", "run daemonized in the background") { |d|
            options[:daemonize] = d ? true : false
          }

          opts.on("-u", "--user NAME", "User to run daemon as (use with -g)") { |u|
            options[:user] = u
          }

          opts.on("-g", "--group NAME", "Group to run daemon as (use with -u)") { |g|
            options[:group] = g
          }

          opts.on("-P", "--pid FILE", "file to store PID (default: rotten_egg.pid)") { |f|
            options[:pid] = f
          }

          opts.on("-l", "--log FILE", "file to store log") { |l|
            options[:log] = l
          }

          opts.separator ""
          opts.separator "Common options:"

          opts.on_tail("-h", "--help", "Show this message") do
            puts opts
            exit
          end

          opts.on_tail("--version", "Show version") do
            puts "RottenEgg #{RottenEgg.version}, release #{RottenEgg.release}"
            exit
          end
        end
        opt_parser.parse! args
        unless options[:config]
          options[:config] = args.last if args.last
        end
        options
      end
    end

    attr_writer :options

    def initialize(options)
      @options = options
    end

    def options
      @options ||= parse_options(ARGV)
    end

    def self.start(options = nil)
      new(options).start
    end

    def default_options
      {
        :environment          => :development,
        :pid                  => nil,
        :daemonize            => false,
        :server               => "thin",
        :port                 => 14720,
        :host                 => "0.0.0.0",
        :log                  => nil,
        :config               => nil,
        :auth_file            => nil,
        :working_directory    => ENV['PWD'],
        :page_size            => 50
      }
    end

    def start
#      if options[:debug]
#        $DEBUG = true
#        require 'pp'
#        p options[:server]
#        pp wrapped_app
#        pp app
#      end
#
#      if options[:warn]
#        $-w = true
#      end

      options[:working_directory] = File.expand_path options[:working_directory], ENV['PWD']
      options[:working_directory] = Util.format_path options[:working_directory] 

      options[:paging_size] = options[:paging_size].to_i <= 0 ? 50 : options[:paging_size].to_i
      
      Application.set :apps_setting, {}
      Application.set :paging_size, options[:paging_size]
      if options[:config]
        unless File.exist? options[:config]
          abort "app configuration #{options[:config]} not found"
        else
          setting                                  = begin
            AppSetting.parse! options[:config], true
          rescue Exception => e
            abort "#{e.message}"
          end
          name = setting.delete(:name)
          Application.apps_setting[name]  = setting
        end
      end

      if options[:auth_file]
        unless File.exist? options[:auth_file]
          abort "app auth file #{options[:auth_file]} not found"
        else
          Application.set :auth_user, YAML::load_file(options[:auth_file])
        end
      else
        Application.set :auth_user, {"user" => "rotten", "password" => "egg"}
      end

      options.delete :auth_file

      daemonize_app if options[:daemonize]
      write_pid if options[:pid]

      FileUtils.mkdir_p options[:working_directory] unless File.directory? options[:working_directory]
      options[:log] = "#{options[:working_directory]}/#{options[:environment]}.log" unless options[:log]
      log_file = options[:log]
      FileUtils.mkdir_p File.dirname(log_file) unless File.directory? File.dirname(log_file)

      if options[:daemonize] or options[:environment].to_s == "production"
        $old_stdout = $stdout # in case you want to turn off traces
        $stdout = File.new(log_file, 'w')
        $stdout.sync = true
        $stderr.reopen($stdout)
        $stderr = $stdout
      end

      Application.run! options
    end

    private

    def parse_options(args)
      options = default_options
      options.merge! opt_parser.parse! args
      ENV["RACK_ENV"] = options[:environment].to_s
      options
    end

    def opt_parser
      Options.new
    end

    def daemonize_app
      if RUBY_VERSION < "1.9"
        exit if fork
        Process.setsid
        exit if fork
        Dir.chdir "/"
        File.umask 0000
        STDIN.reopen "/dev/null"
        STDOUT.reopen "/dev/null", "a"
        STDERR.reopen "/dev/null", "a"
      else
        Process.daemon
      end
    end

    def write_pid
      File.open(options[:pid], 'w') { |f| f.write("#{Process.pid}") }
      at_exit { File.delete(options[:pid]) if File.exist?(options[:pid]) }
    end
  end
end