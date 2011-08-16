# encoding: utf-8

require 'yaml'
require 'sinatra'
gem 'activesupport', '3.0.9'
require "active_support"
require 'sinatra_more'
require 'haml'
require 'yajl/json_gem'

APP_ROOT  = File.expand_path(File.join(File.dirname(__FILE__), '../..'))

module RottenEgg
  class Application < Sinatra::Base

    set :root, APP_ROOT
    set :app_name, "Rotten egg"
    set :changed_entries, []
    set :ftp_utils, {}
    set :msg_logger, MessageLogger.new
    set :running_status, false

    if development?
      reset!
#      use Rack::Lint
      use Rack::Reloader, 0
      use Rack::CommonLogger
    end

    # secret => rand(16**64).to_s(16)
    use Rack::Session::Cookie, :key => 'rotten.egg.session',
                               :path => '/',
                               :expire_after => 30 * 24 * 3600,
                               :secret => '6e4b1a7b6328a6175b93b7c95ea75b8356f4f30e37b9d06c23d72d1244a5a9aa'

    #cregister Sinatra::RespondTo

    register SinatraMore::MarkupPlugin
    register SinatraMore::RenderPlugin
    register SinatraMore::WardenPlugin
    SinatraMore::WardenPlugin::PasswordStrategy.user_class = User

    configure do;end

    helpers do
      def hash_to_tree_store(value)
        return value unless value.is_a?(Hash)
        result = value.inject([]) do |memo, (k,v)|
          if v.is_a?(Hash)
            memo << { :text => k, :cls => "folder", :children => hash_to_tree_store(v) }
          else
            memo << { :text => "#{k}: #{(k == :password) ? '******' : v}", :leaf => true, :cls => "file" }
          end
          memo
        end
        result
      end

      def who_is_running()
        who = ''
        settings.apps_setting.each do |key, setting|
           if setting[:running] == true
              who = key.to_s
              break
           end
        end
        who
      end
    end

    before do
      routes = %w(/login /authenticate /logout)
      reg_exps = routes.collect { |route| %r(\A#{route}) }
      filters = reg_exps.reject { |exp| (exp =~ request.path).nil? ? true : false }
      if filters.empty?
        redirect '/login' unless authenticated?
      end
    end

    get '/' do
      haml :index
    end

    get '/login/?' do
      haml_template 'session/login'
    end

#    post '/unauthenticated' do
#      respond_to do |format|
#        format.html {}
#        format.json {}
#      end
#    end

    post '/authenticate/?' do
      content_type :json, :charset => 'utf-8'
      if User.auth?(params[:username], params[:password])
        authenticate_user!
        {:success => true, :msg => "logged in"}.to_json
      else
        {:msg => "login failed"}.to_json
      end
    end

    get '/logout/?' do
      logout_user!
      redirect '/login'
    end

    get '/apps_list/?' do
      content_type :json, :charset => 'utf-8'
      hash_to_tree_store(settings.apps_setting).to_json
    end

    get '/files/?' do
      mode, status = params[:action_mode], params[:status]
      changes = if settings.changed_entries.empty?
                  []
                else
                  case mode
                    when "M", "A", "D"
                      settings.changed_entries.collect { |item| item[:action] == mode ? item : nil }.compact
                    else
                      settings.changed_entries
                  end
                end
      changes = if changes.empty?# unless
                  []
                else
                  case status
                    when "pending", "success", "failed"
                      changes.collect { |item| item[:status] == status.to_sym ? item : nil }.compact
                    else
                      changes
                  end
                end

      paging_column = changes.each_slice(settings.paging_size).collect { |files| files }
      page = params[:page].to_i
      if page <= 1
        page = 1
      elsif page >= paging_column.size
        page = paging_column.size
      end
      page = page - 1
      content_type :json, :charset => 'utf-8'
      { :success => true, :files => paging_column[page], :total => changes.size }.to_json
    end

    get '/logs?' do
      #content_type :html, :charset => 'utf-8'
      haml settings.msg_logger.pop_all.reverse.join("\n"), :layout => false
    end

    get '/running_status?' do
      haml settings.running_status.to_s, :layout => false
    end

    get '/turnoff' do
      settings.running_status = false
      settings.apps_setting.each do |key, setting|
        setting.update(:running => false)
        settings.ftp_utils[key] = nil
      end
      settings.changed_entries.clear
      settings.msg_logger.clear!
      haml 'ok', :layout => false
    end

    # http://www.sencha.com/forum/archive/index.php/t-120201.html
    # http://stackoverflow.com/questions/4859502/upload-files-by-extjs-ajax-request-and-asp-net-mvc-without-reload-page-ajax-styl
    post '/cfg_upload/?' do
      # specify content_type to 'text/html' , resolved ''<pre style="word-wrap: break-word; white-space: pre-wrap;">{"success":false,"msg":"Failed to add request"}</pre>' error message.
      content_type :html, :charset => 'utf-8'
      result = begin
        yml_file                     = params["file_path"][:tempfile].read
        setting                      = AppSetting.parse!(yml_file)
        name                         = setting.delete(:name)
        if settings.apps_setting[name] && settings.apps_setting[name][:running] == true
          { :success => true, :egg => 0, :msg => "The app [#{name}] is running, please try upload later." }
        else
          settings.apps_setting[name] = setting
          { :success => true, :egg => 1, :msg => "ok" }
        end
      rescue Exception => e
        { :success => true, :egg => 2, :msg => e.message }
      end

      haml result.to_json
    end

    get '/rm_app/?' do
      content_type :html, :charset => 'utf-8'
      result = begin
        if settings.apps_setting[params[:name]] && settings.apps_setting[params[:name]][:running] == true
          { :egg => "running", :msg => "#{params[:name]} is running, please try later." }
        else
          settings.apps_setting.delete params[:name]
          { :egg => "ok", :msg => "#{params[:name]} remove successfully." }
        end
      rescue Exception => e
        { :egg => "error", :msg => e.message }
      end
      haml result.to_json, :layout => false
    end

    get '/run_app' do
      content_type :html, :charset => 'utf-8'
      if settings.running_status == true
        result = {:egg => "running", :msg => "That's a thread[#{who_is_running}] is running, please try later."}
      else
        result = begin
          app_setting = settings.apps_setting[params[:name]]
          if app_setting
            if app_setting[:running] == true
              {:egg => "running", :msg => "#{params[:name]} is running, please try later."}
            else

              settings.changed_entries.clear
              settings.ftp_utils.delete params[:name]

              ftp_util = settings.ftp_utils[params[:name]] = Util::FtpTool.new(
                  app_setting[:ftp][:host],
                  app_setting[:ftp][:port],
                  app_setting[:ftp][:user],
                  app_setting[:ftp][:password],
                  :msg_logger => settings.msg_logger,
                  :passive => app_setting[:ftp][:passive],
                  :verbose => production?
              )
              settings.msg_logger.clear!

              # begin running
              app_setting.update(:running => true)
              settings.running_status = true

              dld_ver_status = ftp_util.download_version_file(settings.working_directory, app_setting[:scm][:remote_version_file])
              status = case dld_ver_status
                         when :initial
                           app_setting[:scm].update(:remote_commit => nil)
                         when :success
                           if File.exist?(settings.working_directory + app_setting[:scm][:remote_version_file])
                             app_setting[:scm].update(:remote_commit => File.read(settings.working_directory + app_setting[:scm][:remote_version_file]).chomp)
                             true
                           else
                             false
                           end
                         else # :failure, :ftp_connect_failure
                           false
                       end
              if status
                settings.changed_entries = Scm.get_changes(app_setting[:scm])
                puts "goes here"
                if settings.changed_entries.empty?
                  app_setting.update(:running => false)
                  settings.running_status = false
                  {:egg => "empty", :msg => "no files has been changed"}
                else
                  # fork {}
                  Thread.fork {
                    result = ftp_util.apply_changes(app_setting[:scm][:repository], settings.changed_entries)
                    if result
                      File.open(settings.working_directory + app_setting[:name] + "_latest_version.txt", "w") { |f| f.write(app_setting[:scm][:latest_commit]) }
                      upload_version_file_status = ftp_util.update_version_file settings.working_directory + app_setting[:name] + "_latest_version.txt", app_setting[:scm][:remote_version_file]
                    end
                    if upload_version_file_status
                      settings.changed_entries.clear
                      settings.msg_logger.clear!
                    end
                    app_setting.update(:running => false)
                    settings.running_status = false

                  }
                  puts "goes rotten"
                  {:egg => "rotten", :msg => "running..."}
                end
              else
                app_setting.update(:running => false)
                settings.running_status = false
                {:egg => 'failure', :msg => "download remove version file failed"}
              end
            end
          else
            app_setting.update(:running => false)
            settings.running_status = false
            {:egg => "missing", :msg => "#{params[:name]} not exist"}
          end # config setting exist
        rescue Exception => e
          app_setting.update(:running => false)
          settings.running_status = false
          {:egg => "error", :msg => e.message}
        end
      end

      haml result.to_json, :layout => false      
    end

  end
end
