require "digest/sha2"
require "test/unit"
require "rubytahoe"

class TC_ReadOnly < Test::Unit::TestCase

    def setup
        @dir = RubyTahoe.new TahoeServer, TahoeReadOnlyCap if @dir.nil?
    end

    def test_init
        assert_instance_of RubyTahoe::Directory, @dir, "The directory is not what it seems to be"
        assert @dir.readable?, "The test directory is not readable"
        assert !@dir.writeable?, "The test directory is writeable"
        assert !@dir.empty?, "The test directory is empty"
        assert @dir.mutable?, "The directory is not mutable"
        assert !@dir.immutable?, "The directory is immutable"
    end

    def test_empty_directory
        assert @dir.exists?("empty"), "The directory is missing"
        dir = @dir["empty"]
        assert_instance_of RubyTahoe::Directory, dir, "The directory is not what it seems to be"
        assert dir.empty?, "The directory is not empty"
        assert_equal [], dir.list_directory(), "The directory contains children"
        dir.each do |name, object|
            flunk "The directory contains children"
        end
        assert dir.mutable?, "The directory is not mutable"
        assert !dir.immutable?, "The directory is immutable"
    end

    def test_nonempty_directory
        assert @dir.exists?("non-empty"), "The directory is missing"
        dir = @dir["non-empty"]
        assert_instance_of RubyTahoe::Directory, dir, "The directory is not what it seems to be"
        assert !dir.empty?, "The directory is empty"
        assert_equal Array.new(10) { |i| i.to_s }, dir.list_directory.sort, "The directory has the wrong files"
        control = [ ]
        dir.each do |name, object|
            control << name.to_i
            assert_instance_of RubyTahoe::File, dir[name], "The directory does not contain files only"
        end
        assert_equal 0.upto(9).to_a, control.sort, "The directory has the wrong files"
        assert dir.mutable?, "The directory is not mutable"
        assert !dir.immutable?, "The directory is immutable"
    end

    def test_get_immutable
        assert @dir.exists?("immutable-file"), "The file is missing"
        file = @dir["immutable-file"]
        assert_instance_of RubyTahoe::File, file, "The file is not what it seems to be"
        assert !file.mutable?, "The file is mutable"
        assert file.immutable?, "The file is not immutable"
        assert_equal 131072, file.size, "The file size is incorrect"
        assert_equal "64ea8195f0228f2944e83843a75c81f9a2bda06715cf2e20b31ff9a43257a5d2", Digest::SHA256.hexdigest(file.data), "The file is corrupted"
    end

    def test_get_mutable
        assert @dir.exists?("mutable-file"), "The file is missing"
        file = @dir["mutable-file"]
        assert_instance_of RubyTahoe::File, file, "The file is not what it seems to be"
        assert file.mutable?, "The file is not mutable"
        assert !file.immutable?, "The file is immutable"
        assert_equal 131072, file.size, "The file size is incorrect"
        assert_equal "b08d227c299c5d2567ed2ce6952a8aaac9373f73b5a1de87a371d9bd83fa0a2b", Digest::SHA256.hexdigest(file.data), "The file is corrupted"
    end

    def test_get_nonexistant
        assert !@dir.exists?("not-there"), "The object exists"
        assert_raise NotFoundError, "The object could be found" do
            @dir["not-there"]
        end
    end

    def test_mkdir
        assert !@dir.exists?("mkdir-testdir"), "The test directory already exists"
        assert_raise RubyTahoe::ReadOnlyError, "The directory is writeable" do
            @dir.mkdir "mkdir-testdir"
        end
        assert !@dir.exists?("mkdir-testdir"), "The test directory suddenly exists"
    end

    def test_put_file
        assert !@dir.exists?("put-testfile"), "The test file already exists"
        assert_raise RubyTahoe::ReadOnlyError, "The directory is writeable" do
            @dir.put_file "put-testfile", "Created by #{RUBY_VERSION} running #{name}"
        end
        assert !@dir.exists?("put-testfile"), "The test file suddenly exists"
    end

    def test_delete
        assert @dir.exists?("delete-testfile"), "The test file does not exist"
        assert_raise RubyTahoe::ReadOnlyError, "The directory is writeable" do
            @dir.delete("delete-testfile")
        end
        assert @dir.exists?("delete-testfile"), "The test file suddenly disappeared"
    end

end
