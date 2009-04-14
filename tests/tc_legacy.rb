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

require 'test/unit'
require 'rubytahoe'

# fill in your username, password, and valid Root URI to test the Root URI retrieval code
AllMyDataUsername = ""
AllMyDataPassword = ""
AllMyDataURI = ""

class TC_Legacy < Test::Unit::TestCase
  def setup
    @client = RubyTahoe::Directory.new TahoeServer
  end

  def test_allmydata_auth
    unless AllMyDataURI.empty?
      root_uri = RubyTahoe.get_allmydata_root_uri(AllMyDataUsername, AllMyDataPassword)
      assert_equal(AllMyDataURI, root_uri)
    end

    root_uri = RubyTahoe.get_allmydata_root_uri(AllMyDataUsername, AllMyDataPassword + "laksjflkajsdf")
    assert_nil(root_uri)
  end

  def test_file
    contents = "Leroy was here at #{Time.new.to_s}"

    @client.mkdir("/test/")

    # create a file
    @client.put_file("/test/file.txt", contents)

    # fetch it by path
    downloaded_contents = @client.get_file("/test/file.txt")
    assert_equal contents, downloaded_contents

    # check the file size
    size = @client.get_size("/test/file.txt")
    assert_equal(contents.length, size)

    # download from a bogus path
    assert_raise(NotFoundError) {
      @client.get_file("/lkajsdflkjasldkfjaisldfjlk")
    }
  end

  def test_directory
    # create a directory
    @client.mkdir("/test_directory/")

    # create some child directories
    @client.mkdir("/test_directory/mydir1")
    @client.mkdir("/test_directory/mydir2")
    @client.mkdir("/test_directory/mydir3")
    @client.mkdir("/test_directory/another directory")

    # create a couple files
    @client.put_file("/test_directory/myfile1.txt", "leroy was here")
    @client.put_file("/test_directory/myfile2.txt", "and here")
    @client.put_file("/test_directory/myfile3.txt", "and also here")
    @client.put_file("/test_directory/myfile4.txt", "and finally here")

    # create a colliding directory
    assert_raise(ArgumentError) {
      @client.mkdir("/test_directory/myfile4.txt/")
    }

    # create a sub-sub directory
    @client.mkdir("/test_directory/mydir2/another")

    expected_items = ["mydir1/", "mydir2/", "mydir3/", 
      "myfile1.txt", "myfile2.txt", "myfile3.txt", 
      "myfile4.txt", "another directory/"]

    # verify the listing
    subdirid = nil
    items = @client.list_directory("/test_directory/")
    items.each { |item|
      assert_not_nil(expected_items.delete(item))
    }
    assert_equal(0, expected_items.length)

    # list the subdirectory
    subitems = @client.list_directory("/test_directory/mydir2/")

    assert_equal(1, subitems.length)
    assert_equal("another/", subitems[0])

    # list a file
    assert_raise(ArgumentError) {
      @client.list_directory("/test_directory/myfile4.txt")
    }
  end

  def test_delete
    # make a test fileset
    @client.mkdir("/test_deleting_directory/")
    @client.mkdir("/test_deleting_directory/subdir1/")
    @client.mkdir("/test_deleting_directory/subdir2/")
    @client.put_file("/test_deleting_directory/subdir2/file1.txt", "leroy was here")
    @client.mkdir("/test_deleting_directory/subdir3/")
    @client.put_file("/test_deleting_directory/file1.txt", "leroy was here")
    @client.put_file("/test_deleting_directory/file2.txt", "leroy was here")

    # delete some
    @client.delete("/test_deleting_directory/subdir2/")
    @client.delete("/test_deleting_directory/file1.txt")

    # verify the listing
    items = @client.list_directory("/test_deleting_directory/")
    expected_items = ["subdir1/", "subdir3/", "file2.txt"]

    items.each { |key|
      assert_not_nil(expected_items.delete(key))
    }
    assert_equal(0, expected_items.length)

    # check that we got the file in the subdirectory
    assert_raise(NotFoundError) {
      assert_not_equal("leroy was here", @client.get_file("/test_deleting_directory/subdir2/file1.txt"))
    }
  end

  def test_rename
    @client.mkdir("/test_renaming_directory/")
    @client.mkdir("/test_renaming_directory/subdir1")
    @client.mkdir("/test_renaming_directory/subdir2")
    @client.mkdir("/test_renaming_directory/subdir3")
    @client.put_file("/test_renaming_directory/file1.txt", "leroy was here")
    @client.put_file("/test_renaming_directory/file2.txt", "leroy was not here")
    verify_directory_contents("/test_renaming_directory/", ["subdir1/", "subdir2/", "subdir3/", "file1.txt", "file2.txt"])
    verify_directory_contents("/test_renaming_directory/subdir1/",[])

    # rename a file across directories
    @client.rename("/test_renaming_directory/file1.txt", "/test_renaming_directory/subdir1/file1.txt")

    verify_directory_contents("/test_renaming_directory/", ["subdir1/", "subdir2/", "subdir3/", "file2.txt"])
    verify_directory_contents("/test_renaming_directory/subdir1/", ["file1.txt"])
    assert_equal("leroy was here", @client.get_file("/test_renaming_directory/subdir1/file1.txt"))

    # rename the file to a new name
    @client.rename("/test_renaming_directory/subdir1/file1.txt", "/test_renaming_directory/subdir1/file3.txt")
    verify_directory_contents("/test_renaming_directory/subdir1/", ["file3.txt"])
    assert_equal("leroy was here", @client.get_file("/test_renaming_directory/subdir1/file3.txt"))

    # destructive rename over "file2.txt"
    @client.rename("/test_renaming_directory/subdir1/file3.txt", "/test_renaming_directory/file2.txt")
    assert_equal("leroy was here", @client.get_file("/test_renaming_directory/file2.txt"))

    # put some files in subdir2
    @client.put_file("/test_renaming_directory/subdir2/file1.txt", "leroy was here")
    @client.put_file("/test_renaming_directory/subdir2/file2.txt", "and here")
    @client.put_file("/test_renaming_directory/subdir2/file3.txt", "and also here")

    # now rename subdir2 to subdir4
    @client.rename("/test_renaming_directory/subdir2/", "/test_renaming_directory/subdir4/")
    verify_directory_contents("/test_renaming_directory/subdir4/", ["file1.txt", "file2.txt", "file3.txt"])

    # now try to make an impossible tree
    assert_raise(ArgumentError) {
      @client.rename("/test_renaming_directory/", "/test_renaming_directory/subdir1/newdir")
    }
  end

  def test_list_paths_starting_with
    # create a directory
    @client.mkdir("/test_directory/")

    # create some child directories
    @client.mkdir("/test_directory/mydir1")
    @client.mkdir("/test_directory/mydir2")
    @client.mkdir("/test_directory/mydir3")

    # create a couple files
    @client.put_file("/test_directory/mydir2/myfile1.txt", "leroy was here")
    @client.put_file("/test_directory/mydir2/myfile2.txt", "and here")
    @client.put_file("/test_directory/mydir2/myfile3.txt", "and also here")
    @client.put_file("/test_directory/mydir3/myfile4.txt", "and finally here")

    listing = @client.list_paths_starting_with("/test_directory/my")
    correct_listing = ["/test_directory/mydir1/", "/test_directory/mydir2/",
      "/test_directory/mydir3/", "/test_directory/mydir2/myfile1.txt",
      "/test_directory/mydir2/myfile2.txt", "/test_directory/mydir2/myfile3.txt",
      "/test_directory/mydir3/myfile4.txt"]

    assert_equal(correct_listing.sort, listing.sort)
  end

  def test_colon_names
    @client.put_file("/test_file:metadata", "contents");
    assert_equal("contents", @client.get_file("/test_file:metadata"));
  end

  def verify_directory_contents(dirpath, contents)
    expected_items = contents.dup
    items = @client.list_directory(dirpath)
    items.each { |key| assert_not_nil(expected_items.delete(key)) }
    assert_equal(0, expected_items.length)
  end

  def test_delete_missing
    assert_raise(NotFoundError) {
      @client.delete("/totally bogus folder")
    }
  end

  def test_get_missing
    assert_raise(NotFoundError) {
      @client.get_file("/totally bogus file")
    }
  end

  def test_list_missing
    assert_raise(NotFoundError) {
      @client.list_directory("/totally bogus folder/")
    }

    assert_nothing_thrown {
      @client.list_paths_starting_with("/totally bogus folder/")
    }
  end
end

# vim:softtabstop=2:shiftwidth=2
