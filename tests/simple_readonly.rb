#!/usr/bin/ruby -rubygems
# RubyTahoe, unit tests.
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

require "digest/sha2"
require 'test/unit'
require 'rubytahoe'

class TC_Simple_ReadOnly < Test::Unit::TestCase

  def setup
    @client = RubyTahoe.new(TahoeServer, TahoeReadOnlyCap) if @client.nil?
  end

  def test_empty_directory
    assert_equal [], @client.list_directory("/empty"), "The directory is not empty"
  end

  def test_nonempty_directory
    assert_equal 0.upto(9).to_a.map{ |x| x.to_s}, @client.list_directory("/non-empty").sort, "The directory does not contain the right files"
  end

  def test_get_file
    assert_equal "64ea8195f0228f2944e83843a75c81f9a2bda06715cf2e20b31ff9a43257a5d2", Digest::SHA256.hexdigest(@client.get_file("/immutable-file")), "The file is corrupted"
  end

  def test_get_nonexistant
    assert_raise NotFoundError do
      @client.get_file("/somefile")
    end
  end

end

# vim:softtabstop=2:shiftwidth=2
