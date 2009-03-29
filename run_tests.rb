#!/usr/bin/env ruby

require "test/unit"

if ARGV[0]
  TahoeServer = ARGV[0]
else
  TahoeServer = 'http://testgrid.allmydata.org:3567/'
end

puts "Web API URI: #{TahoeServer}"

Dir.foreach "tests" do |file|
  next if file[0] == ?.
  require "tests/#{file}"
end

# vim:softtabstop=2:shiftwidth=2
