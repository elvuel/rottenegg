# encoding: utf-8

module RottenEgg

  class MessageLogger

    def initialize
      @messages = []
    end

    def counts
      @messages.length
    end

    def add(msg)
      @messages << msg
    end

    def clear!
      @messages.clear
    end

    def tops(size=0)
      size = 0 if size < 0
      @messages.slice!(0..size).compact
    end

    def first
      tops
    end

    def pop_all
      tops(counts-1)
    end
  end
end