#!/usr/bin/env ruby

require "test/unit"

if ARGV[0]
  TahoeServer = ARGV[0]
else
  TahoeServer = 'http://testgrid.allmydata.org:3567/'
end
TahoeReadOnlyCap = "URI:DIR2-RO:as2uresriaeed44mvdstfu46je:uhtfyxhbdwbp4zpeda5hydccwt4szrx6dxl27xkmswxo7xmbus4a"

puts "Web API URI: #{TahoeServer}"
puts "Read onyl cap: #{TahoeReadOnlyCap}"

Dir.foreach "tests" do |file|
  next if file[0] == ?.
  require "tests/#{file}"
end

# vim:softtabstop=2:shiftwidth=2
