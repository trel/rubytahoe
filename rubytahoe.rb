#!/usr/bin/ruby
# RubyTahoe, a simple library that makes it easy to store and retrieve information
# from a Tahoe LAFS grid node using the Tahoe WebAPI.
#
# Copyright © 2008-2009, Ian Levesque. All Rights Reserved.
# ian@ephemeronindustries.com
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# - Redistributions of source code must retain the above copyright notice, this list
#   of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright notice, this list
#   of conditions and the following disclaimer in the documentation and/or other materials
#   provided with the distribution.
# - Neither the name of the Ephemeron Industries nor the names of its contributors may be
#   used to endorse or promote products derived from this software without specific prior
#   written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
# THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'net/http'
require 'net/https'
require 'uri'
require 'json/add/core'

class NotFoundError < RuntimeError; end

class String
  unless method_defined?(:end_with?)
    # Compatibility with 1.9
    def end_with?(other)
      other = other.to_s
      self[-other.size, other.size] == other
    end
  end

  unless method_defined?(:start_with?)
    # Compatibility with 1.9
    def start_with?(other)
      other = other.to_s
      self[0, other.size] == other
    end
  end
end

module RubyTahoe

  def self.get_allmydata_root_uri(email, password)
    http = Net::HTTP.new("www.allmydata.com", 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE # change this if you're concerned about MITM
    req = Net::HTTP::Post.new("/native_client.php")
    req.form_data = {'action'=>'authenticate', 'email'=>email, 'passwd' => password, 'submit' => 'Login'}
    res = http.request(req)
    res.value
    if res.body != "0"
      res.body
    else
      nil
    end
  end

  def self.new *args
    Object.new *args
  end

  class Object

    # The read/write cap
    attr_reader :rw_cap

    # The readonly cap
    attr_reader :ro_cap

    # The repair cap
    attr_reader :repair_cap

    #
    # Returns true when the object is readable (i.e. it has a read cap)
    #
    def readable?
      not @ro_cap.nil?
    end

    #
    # Returns true when the object is writeable (i.e. it has a write cap)
    #
    def writeable?
      not @rw_cap.nil?
    end

    #
    # Returns true when the file is a directory or a mutable file.
    #
    def mutable?
      @mutable
    end

    #
    # Returns true when the file is an immutable file.
    #
    def immutable
      not @mutable
    end

    #
    # Returns the cap for the file with the highest permission (read/write cap
    # > readonly cap > repair cap).
    #
    def cap
      return @rw_cap unless @rw_cap.nil?
      return @ro_cap unless @ro_cap.nil?
      @repair_cap
    end

    alias :root_uri :cap

    #
    # Returns a new instance of RubyTahoe::File or RubyTahoe::Directory,
    # depending on the given cap.
    #
    def self.new server_url, cap
      server_url = URI.parse server_url unless server_url.is_a? URI::HTTP
      data = Net::HTTP.start(server_url.host, server_url.port) do |http|
        response, data = http.get "/uri/#{cap}?t=json"
        raise NotFoundError unless response.code == "200"
        data
      end
      data = JSON.parse(data)
      return self.from_json server_url, data
    end

    #
    # Returns a new instance of RubyTahoe::File or RubyTahoe::Directory from
    # parsed JSON data.
    #
    def self.from_json server_url, data
      object = if data[0] == "dirnode"
        Directory.allocate
      else
        File.allocate
      end
      object.send :initialize, server_url, data[1]
      object
    end

    def initialize server_url, data
      @server_url = server_url
      @rw_cap = data["rw_uri"]
      @ro_cap = data["ro_uri"]
      @repair_cap = data["repair_cap"]
      @mutable = data["mutable"]
    end

  end

  class File < Object
  end

  class Directory < Object

    def put_file(path, contents)
      url = build_path_url(path)
      put_file_url(url, contents)
    end

    def put_file_url(url, contents)
      fileid = nil
      Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        headers = {'Content-Type' => 'application/octet-stream'}
        response = http.send_request('PUT', url, contents, headers)
        response.value
        fileid = response.body
      end
    fileid
    end

    def get_file(path)
      get_file_url(build_path_url(path))
    end

    def get_file_url(url)
      res = Net::HTTP.start(@server_url.host, @server_url.port) {|http|
        http.get(url)
      }
      raise NotFoundError if res.code == "404"
      raise NotFoundError if res.code == "301"
      raise NotFoundError if res.code == "300"
      res.value
      res.body
    end

    def build_path_url(path)
      url = "/uri/" + cap + URI.escape(path)
      # singlify any double slashes
      url.sub(/\/\//, '/')
    end

    def mkdir(path)
      realpath = (path.end_with?("/") ? path.chop : path)
      res = Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        http.post(build_path_url(realpath) + "?t=mkdir", nil)
      end
      raise ArgumentError.new("Directory exists") if res.code == "400"
      res.value
      res.body
    end

    def list_directory(path)
      url = build_path_url(path)
      list_directory_url(url)
    end

    def list_directory_url(url)
      res = Net::HTTP.start(@server_url.host, @server_url.port) {|http|
        http.get("#{url}?t=json")
      }
      raise NotFoundError if res.code == "404"
      res.value
      json_info = res.body

      directory_info = JSON.parse(json_info)

      raise ArgumentError.new("Not a directory") unless directory_info[0] == "dirnode"

      entries = []

      directory_info[1]["children"].each_key { |filename|
        if directory_info[1]["children"][filename][0] == "dirnode"
          entries << (filename + "/")
        else
          entries << filename
        end
      }

      entries
    end

    def delete(path)
      url = build_path_url(path)

      Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        response = http.send_request('DELETE', url)
        raise NotFoundError if response.code == "404"
        raise NotFoundError if response.code == "301"
        raise NotFoundError if response.code == "300"
        response.value
      end
    end

    # this adds a new hardlink and removes the old one
    def rename(oldpath, newpath)
      # make sure you're not renaming a parent directory underneath itself
      raise ArgumentError.new("Cannot rename a parent into a child of itself") if newpath.start_with?(oldpath) && newpath[oldpath.length-1] == 47 #'/'

      # get the old cap URI
      url = build_path_url(oldpath)
      res = Net::HTTP.start(@server_url.host, @server_url.port) {|http|
        http.get(url + "?t=json")
      }
      res.value

      info = JSON.parse(res.body)
      if info[0] == "dirnode"
        cap = info[1]["rw_uri"]
      else
        cap = info[1]["ro_uri"]
      end

      url = build_path_url(newpath)
      url.chop! while url.end_with?("/")

      # add the new link
      Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        headers = {'Content-Type' => 'text/plain'}
        response = http.send_request('PUT', url + "?t=uri", cap, headers)
        response.value # you get a 500 server error if you try to destructively rename over a directory
      end

      # then remove the old
      delete(oldpath)
    end

    def get_size(path)
      url = build_path_url(path)
      res = Net::HTTP.start(@server_url.host, @server_url.port) {|http|
        http.get(url + "?t=json")
      }
      res.value

      info = JSON.parse(res.body)
      raise ArgumentError.new("Not a file") if info[0] == "dirnode"

      info[1]["size"]
    end

  def list_paths_starting_with(prefix)
      parent = prefix[0..prefix.rindex('/')]

      paths = []
      begin
        list_directory(parent).each { |name|
          path = parent + name

          if(path.start_with? prefix)
            paths << path
            if(path.end_with? "/")
              list_paths_starting_with(path).each { |path|
                paths << path
              }
            end
          end
        }
      rescue NotFoundError
        # we can validly have no matching directories
      end

      paths
    end

  end

end

# vim:softtabstop=2:shiftwidth=2
