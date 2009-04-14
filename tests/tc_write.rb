require "digest/sha2"
require "test/unit"
require "rubytahoe"

class TC_Write < Test::Unit::TestCase

    def get_random_data
        Digest::SHA512.hexdigest("#{Process.pid} #{Process.uid} #{Process.gid} #{rand}").slice(0, rand(128) + 1)
    end

    def test_empty_directory
        dir = RubyTahoe::Directory.new TahoeServer
        assert_instance_of RubyTahoe::Directory, dir, "The directory is not what it seems to be"
        assert dir.readable?, "The test directory is not readable"
        assert dir.writeable?, "The test directory is not writeable"
        assert dir.empty?, "The test directory is notempty"
        assert_equal [], dir.list_directory, "The directory contains children"
        dir.each do |name, object|
            flunk "The directory contains children"
        end
        assert dir.mutable?, "The directory is not mutable"
        assert !dir.immutable?, "The directory is immutable"
    end

    def test_immutable_file
        contents = get_random_data
        file = RubyTahoe::File.new TahoeServer, contents
        file = RubyTahoe.new TahoeServer, file.cap
        assert_instance_of RubyTahoe::File, file, "The file is not what it seems to be"
        assert_equal contents.size, file.size, "The file size is wrong"
        assert_equal contents, file.data, "The file got corrupted"
        assert !file.mutable?, "The file is mutable"
        assert file.immutable?, "The file is not immutable"
    end

    def test_mutable_file
        contents = get_random_data
        file = RubyTahoe::File.new TahoeServer, contents, true
        file = RubyTahoe.new TahoeServer, file.cap
        assert_instance_of RubyTahoe::File, file, "The file is not what it seems to be"
        assert_equal contents.size, file.size, "The file size is wrong"
        assert_equal contents, file.data, "The file got corrupted"
        assert file.mutable?, "The file is not mutable"
        assert !file.immutable?, "The file is not immutable"
    end

    def test_directory_files
        # Create a directory with 5 files
        dir = RubyTahoe::Directory.new TahoeServer
        files = Array.new 5 do |i|
            contents = get_random_data
            file = RubyTahoe::File.new TahoeServer, contents
            dir[i.to_s] = file
            contents
        end
        # Test the files
        assert !dir.empty?, "The directory is empty"
        assert_equal Array.new(5) { |i| i.to_s }.sort, dir.list_directory.sort, "The directory contains the wrong files"
        dir.each do |name, object|
            assert_instance_of RubyTahoe::File, object
            assert_equal files[name.to_i].size, object.size, "The file size is wrong"
            assert_equal files[name.to_i], object.data, "The file got corrupted"
            assert !object.mutable?, "The file is mutable"
            assert object.immutable?, "The file is not immutable"
        end
        # Create new files with the contents being reversed and using another method
        5.times do |i|
            dir.put_file i.to_s, files[i].reverse
        end
        # Verify the new files
        dir.each do |name, object|
            assert_instance_of RubyTahoe::File, object
            assert_equal files[name.to_i].size, object.size, "The file size is wrong"
            assert_equal files[name.to_i].reverse, object.data, "The file got corrupted"
            assert !object.mutable?, "The file is mutable"
            assert object.immutable?, "The file is not immutable"
        end
        # Delete the files
        5.times do |i|
            dir.delete i.to_s
        end
        # Verify that the directory is empty again
        assert dir.empty?, "The directory is not empty"
        assert_equal [], dir.list_directory, "The directory contains children"
        dir.each do |name, object|
            flunk "The directory contains children"
        end
    end

    def test_directory_subdirectories
        # Create a directory with 10 subdirectories, using two different ways
        # Every even directory contains a file for added fun
        files = Array.new 5 do |i|
            get_random_data
        end
        dir = RubyTahoe::Directory.new TahoeServer
        5.times do |i|
            dir.mkdir i.to_s
            dir[i.to_s].put_file "testfile", files[i/2] if i % 2 == 0
        end
        5.times do |i|
            i += 5
            subdir = RubyTahoe::Directory.new TahoeServer
            dir[i.to_s] = subdir
            if i % 2 == 0
                file = RubyTahoe::File.new TahoeServer, files[i/2]
                subdir["testfile"] = file
            end
        end
        # Check the directory
        assert !dir.empty?, "The directory is empty"
        assert_equal Array.new(10) { |i| "#{i}/" }.sort, dir.list_directory.sort, "The directory contains the wrong subdirectories"
        dir.each do |name, object|
            assert_instance_of RubyTahoe::Directory, object, "The directory is not what it seems to be"
            if name.to_i % 2 == 0
                assert !object.empty?, "The directory is not empty"
                assert object.exists?("testfile"), "The testfile does not exist"
                assert_equal ["testfile"], object.list_directory, "The directory contains the wrong files"
                file = object["testfile"]
                assert_equal files[name.to_i/2].size, file.size, "The file size is wrong"
                assert_equal files[name.to_i/2], file.data, "The file got corrupted"
                assert !file.mutable?, "The file is mutable"
                assert file.immutable?, "The file is not immutable"
            else
                assert object.empty?, "The directory is not empty"
                object.each do |name2, object2|
                    flunk "The directory contains children"
                end
            end
            assert object.mutable?, "The directory is not mutable"
            assert !object.immutable?, "The directory is immutable"
        end
        # Empty the directory
        10.times do |i|
            dir.delete i.to_s
        end
        # Verify that the directory is empty again
        assert dir.empty?, "The directory is not empty"
        dir.each do |name, object|
            flunk "THe directory contains children"
        end
    end

    def test_rename_file
        # Create a directory with 10 files and rename them
        dir = RubyTahoe::Directory.new TahoeServer
        files = Array.new 5 do |i|
            i += 5
            contents = get_random_data
            dir.put_file i.to_s, contents
            contents
        end
        5.times do |i|
            j = i + 5
            dir.rename j.to_s, i.to_s
        end
        # Check directory
        assert !dir.empty?, "The directory is empty"
        assert_equal Array.new(5) { |i| i.to_s }.sort, dir.list_directory.sort, "The directory contains the wrong files"
        dir.each do |name, object|
            assert_instance_of RubyTahoe::File, object, "The file is not what it seems to be"
            assert_equal files[name.to_i].size, object.size, "The file size is wrong"
            assert_equal files[name.to_i], object.data, "The file got corrupted"
            assert !object.mutable?, "The file is mutable"
            assert object.immutable?, "The file is not immutable!"
        end
    end

    def missing_file
        dir = RubyTahoe::Directory.new TahoeServer
        assert !dir.exists?("testfile"), "The test file exists"
        assert_raise NotFoundError, "The test file exists" do
            dir.rename "testfile", "testfile2"
        end
        assert !dir.exists?("testfile"), "The test file suddenly exists"
        assert !dir.exists?("testfile2"), "The new test file suddenly exists"
        assert_raise NotFoundError, "The test file exists" do
            dir.delete "testfile2"
        end
        assert !dir.exists?("testfile2"), "The test file suddenly exists"
    end

end
