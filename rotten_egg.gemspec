# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "rotten_egg/version"

Gem::Specification.new do |s|
  s.name        = "rottenegg"
  s.version     = RottenEgg::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["elvuel"]
  s.email       = ["elvuel@gmail.com"]
  s.homepage    = "http://elvuel.com"
  s.summary     = %q{Upload SCM files via FTP}
  s.description = %q{Upload SCM files via FTP}

  s.required_ruby_version     = '>= 1.8.7'
  s.required_rubygems_version = ">= 1.3.6"

  s.rubyforge_project = "rotten_egg"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  
  s.add_dependency 'thin'
  s.add_dependency 'sinatra', '>= 1.2.6'
  s.add_dependency 'tmail'
  s.add_dependency 'i18n'
  s.add_dependency 'activesupport', '3.0.9'
  s.add_dependency 'sinatra_more', ">= 0.3.43"
  s.add_dependency 'haml', ">= 3.1.1"
#  s.add_dependency 'net-sftp', ">= 2.0.5"
  s.add_dependency 'warden', ">= 1.0.4"
  s.add_dependency 'nokogiri'
  s.add_dependency 'yajl-ruby'
end
