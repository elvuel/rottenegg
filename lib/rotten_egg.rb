# encoding: utf-8
require 'rubygems' unless defined? Gem

module RottenEgg

  autoload :AppSetting,       File.expand_path('../rotten_egg/app_setting',     __FILE__)
  autoload :MessageLogger,    File.expand_path('../rotten_egg/message_logger',  __FILE__)
  autoload :Scm,              File.expand_path('../rotten_egg/scm',             __FILE__)
  autoload :Util,             File.expand_path('../rotten_egg/util',            __FILE__)
  autoload :User,             File.expand_path('../rotten_egg/user',            __FILE__)
  autoload :Application,      File.expand_path('../rotten_egg/application',     __FILE__)
  autoload :Server,           File.expand_path('../rotten_egg/server',          __FILE__)

end