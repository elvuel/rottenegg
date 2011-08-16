# encoding: utf-8
module RottenEgg
  class User
    @@users = {}
    attr_accessor :id
    attr_reader :name

    def initialize(name="rotten")
      @name = name
      @id   = 14720
    end

    def self.authenticate(username, password)
      if username == Application.auth_user["user"] && password == Application.auth_user["password"]
        usr             = User.new(username)
        @@users[usr.id] = usr
      else
        nil
      end
    end

    def self.auth?(username, password)
      username == Application.auth_user["user"] && password == Application.auth_user["password"]
    end

    def self.find(id)
      @@users[id]
    end
  end
end