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

  class ReadOnlyError < RuntimeError
  end

  def self.get_allmydata_root_uri(email, password)
    require "net/https"
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
    def immutable?
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
    def self.new server_url, cap = nil
      return Directory.new(server_url) if cap.nil?
      server_url = URI.parse server_url unless server_url.is_a? URI::Generic
      data = Net::HTTP.start(server_url.host, server_url.port) do |http|
        response, data = http.get "/uri/#{cap}?t=json"
        raise NotFoundError unless response.code == "200"
        data
      end
      data = JSON.parse(data)
      return self.from_json(server_url, data)
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

    # :nodoc
    def initialize server_url, data
      @server_url = server_url
      @rw_cap = data["rw_uri"]
      @ro_cap = data["ro_uri"]
      @repair_cap = data["verify_uri"]
      @mutable = data["mutable"]
    end

    #
    # Checks the object and returns the results hash as documented at
    # http://allmydata.org/source/tahoe/trunk/docs/frontends/webapi.txt in the
    # "Debugging and Testing Features" section.
    # If verify is true, every bit will be downloaded and verified.
    # If add_lease is true, a/the lease will be added/renewed
    #
    def check verify = false, add_lease = false
      data = Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        http.read_timeout = 7200
        response, data = http.post "/uri/#{cap}?t=check&verify=#{verify}&add-lease=#{add_lease}&output=JSON", nil
        data
      end
      data = JSON.parse data
      data["results"]
    end

    #
    # Similar to check, this function tries to repair damaged files. It returns
    # true on success, false in case of an error and nil if no repair was
    # needed.
    #
    def repair! verify = false, add_lease = false
      data = Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        http.read_timeout = 7200
        response, data = http.post "/uri/#{cap}?t=check&repair=true&verify=#{verify}&add-lease=#{add_lease}&output=JSON", nil
        data
      end
      data = JSON.parse data
      if data["repair-attempted"]
        if data["repair_successful"]
          true
        else
          false
        end
      else
        nil
      end
    end

    #
    # Checks whether an object is healthy or not
    #
    def healthy?
      check()["healthy"]
    end

    alias :healthy! :repair!

  end

  class File < Object

    #
    # Creates a new file containing data. If mutable is set to true, a mutable
    # file will be created.
    #
    def self.new server_url, data, mutable = false
      server_url = URI.parse server_url unless server_url.is_a? URI::Generic
      data = Net::HTTP.start(server_url.host, server_url.port) do |http|
        headers = {"Content-Type" => "application/octet-stream"}
        http.read_timeout = 7200
        response, data = if mutable
          http.send_request "PUT", "/uri?mutable=#{mutable}", data, headers
        else
          http.send_request "PUT", "/uri", data, headers
        end
        data
      end
      super server_url, data
    end

    # :nodoc
    def initialize server_url, data
      super server_url, data
      @size = data["size"] unless data["size"] == "?"
    end

    #
    # Returns the size of a file. As mutable files can change in size, their
    # size needs to be re-fetched every time. This is done by issuing a HEAD
    # request.
    #
    def size
      unless @size.nil?
        @size
      else
        Net::HTTP.start(@server_url.host, @server_url.port) do |http|
          http.read_timeout = 7200
          response = http.head "/uri/#{cap}"
          response["Content-Length"].to_i
        end
      end
    end

    #
    # Returns the contents of the file.
    #
    def data
      Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        http.read_timeout = 7200
        response, data = http.get "/uri/#{cap}"
        data
      end
    end

  end

  class Directory < Object

    #
    # Creates a new empty directory.
    #
    def self.new server_url
      server_url = URI.parse server_url unless server_url.is_a? URI::Generic
      data = Net::HTTP.start(server_url.host, server_url.port) do |http|
        response, data = http.post "/uri?t=mkdir", nil
        data
      end
      super server_url, data
    end

    #
    # Returns true when the directory is empty.
    #
    def empty?
      data = Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        response, data = http.get "/uri/#{cap}?t=json"
        data
      end
      data = JSON.parse data
      data[1]["children"].empty?
    end

    #
    # Returns true if the directory or file specified by path exists.
    #
    def exists? path
      begin
        self[path]
      rescue NotFoundError
        return false
      end
      true
    end

    #
    # Returns a Directory or File object for the specified path. Raises
    # NotFoundError if the path does not exist.
    #
    def [] path
      data = Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        response, data = http.get "#{build_path_url(path)}?t=json"
        raise NotFoundError unless response.code == "200"
        data
      end
      Object.from_json @server_url, JSON.parse(data)
    end

    #
    # Attaches the given object or cap at the specified path
    #
    def []= path, object
      raise ReadOnlyError unless writeable?
      add_cap = if object.respond_to? :cap
        object.cap
      else
        object
      end
      Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        response = http.send_request "PUT", build_path_url(path) + "?t=uri", add_cap
      end
      object
    end

    #
    # Creates a new file containing data at path. If mutable is set to true, a
    # mutable file is created.
    #
    def put_file path, data, mutable = false
      file = File.new @server_url, data, mutable
      self[path] = file
      file.cap
    end

    #
    # Returns the size of the file at path. Raises NotFoundError if the path
    # does not exist and ArgumentError if the path is a directory.
    #
    def get_size path
      file = self[path]
      raise ArgumentError.new("Not a file") unless file.is_a? File
      file.size
    end

    #
    # Retrieves the content of the file at path. Raises NotFoundError if the
    # path does not exist.
    #
    def get_file path
      self[path].data
    end

    #
    # Creates a new, empty directory at the specified path and returns the
    # Directory object for the new directory.
    #
    def mkdir(path)
      raise ReadOnlyError unless writeable?
      realpath = (path.end_with?("/") ? path.chop : path)
      response, data = Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        http.post(build_path_url(realpath) + "?t=mkdir", nil)
      end
      raise ArgumentError.new("Directory exists") if response.code == "400"
      Object.new @server_url, data
    end

    #
    # Yields name and object for each childnode in the directory.
    #
    def each
      data = Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        response, data = http.get "/uri/#{cap}?t=json"
        data
      end
      data = JSON.parse(data)
      data[1]["children"].each_pair do |name, child|
        yield name, Object.from_json(@server_url, child)
      end
    end

    #
    # Lists the directory specified by path, or the current directory if no
    # path is given.
    #
    def list_directory path = "/"
      path.chomp!"/"
      if path.empty?
        dir = self
      else
        dir = self[path]
      end
      raise ArgumentError.new("Not a directory") unless dir.is_a? Directory
      children = []
      dir.each do |name, child|
        name += "/" if child.is_a? Directory
        children << name
      end
      children
    end

    #
    # Lists all paths starting with the specified path.
    #
    def list_paths_starting_with prefix = "/"
      result = []
      path = prefix.split "/"
      prefix = path.pop || ""
      if path.empty?
        dir = self
      else
        dir = self[path.join("/")]
        return [] unless dir.is_a? Directory
      end
      dir.each do |name, child|
        next unless name.start_with? prefix
        name = (path + [name]).join("/")
        if child.is_a? Directory
            name += "/"
            children = child.list_paths_starting_with
            children.map! do |x|
              name + x
            end
            result += children
        end
        result << name
      end
      result
    end

    #
    # Deletes the element at path.
    #
    def delete path
      raise ReadOnlyError unless writeable?
      Net::HTTP.start(@server_url.host, @server_url.port) do |http|
        response = http.send_request "DELETE", build_path_url(path)
        raise NotFoundError if response.code == "404"
        raise NotFoundError if response.code == "301"
        raise NotFoundError if response.code == "300"
      end
    end

    #
    # This adds a new hardlink and removes the old one, as there is no direct
    # rename operation for tahoe.
    #
    def rename oldpath, newpath
      # Make sure you're not renaming a parent directory underneath itself
      raise ArgumentError.new("Cannot rename a parent into a child of itself") if newpath.start_with?(oldpath) && newpath[oldpath.length-1] == ?/

      object = self[oldpath]
      self[newpath] = object
      delete oldpath
    end

    private
    def build_path_url(path)
      url = "/uri/#{cap}/#{URI.escape(path)}"
      # singlify any double slashes
      url.sub(/\/\//, '/')
    end

  end

end

# vim:softtabstop=2:shiftwidth=2
